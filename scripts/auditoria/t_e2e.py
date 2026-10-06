"""
Testes de ponta a ponta no navegador (Playwright + Edge) com o app web ligado ao Supabase real:
login pela tela, validações de formulário, busca, estados vazio/erro/carregando, favoritar, avaliar, sair.

Pré-requisito: app/build/web_real servido em http://127.0.0.1:8790 (flutter build web com SUPABASE_URL e a chave publicável).
Cria um usuário e postos fictícios (dados_teste) e apaga tudo no fim.

Uso: python scripts/auditoria/t_e2e.py
"""
from __future__ import annotations

import re
import sys
import time

from playwright.sync_api import sync_playwright

import comum
import dados_teste as dt
from comum import ALTA, BAIXA, CRITICA, EVIDENCIAS, MEDIA, Suite

BASE = "http://127.0.0.1:8790/#"
ARGS = ["--enable-unsafe-swiftshader", "--use-angle=swiftshader"]
PASTA = EVIDENCIAS / "e2e"


class App:
    def __init__(self, nav, largura=390, altura=844, logado_como=None):
        self.ctx = nav.new_context(viewport={"width": largura, "height": altura}, locale="pt-BR", permissions=["geolocation"],
                                   geolocation={"latitude": -3.7627, "longitude": -38.5399})
        self.ctx.add_init_script("localStorage.setItem('flutter.viu_boas_vindas', 'true')")
        self.pg = self.ctx.new_page()
        self.erros_console = []
        self.pg.on("console", lambda m: self.erros_console.append(m.text[:200]) if m.type == "error" else None)

    def abrir(self, rota: str, espera: int = 4000):
        self.pg.goto(BASE + rota)
        self.pg.wait_for_selector("flutter-view", timeout=60000)
        self.pg.wait_for_timeout(espera)
        self.semantica()

    def semantica(self):
        self.pg.evaluate("document.querySelector('flt-semantics-placeholder')?.click()")
        self.pg.wait_for_timeout(800)

    def texto(self) -> str:
        return self.pg.evaluate("""() => (document.querySelector('flt-semantics-host')?.innerText || '') + ' ' +
            [...document.querySelectorAll('[aria-label], [aria-description]')]
              .map(e => (e.getAttribute('aria-label') || '') + ' ' + (e.getAttribute('aria-description') || '')).join(' ')""")

    def esperar_texto(self, trecho: str, ms: int = 15000) -> bool:
        fim = time.time() + ms / 1000
        while time.time() < fim:
            if trecho.lower() in self.texto().lower():
                return True
            self.pg.wait_for_timeout(500)
            self.semantica()
        return False

    def campo(self, rotulo: str, valor: str):
        """Preenche como uma pessoa: clica no campo, seleciona tudo, apaga e digita pelo teclado.
        O campo é achado pelo rótulo; o Flutter tira o rótulo de campos com dica quando há texto, então
        a posição do campo na tela fica guardada na primeira vez."""
        self.semantica()
        sel = "flt-semantics input, flt-semantics textarea"
        indices = self.__dict__.setdefault("_indices", {})
        rotulos = self.pg.evaluate(f"() => [...document.querySelectorAll('{sel}')].map(e => e.getAttribute('aria-label') || '')")
        chave = (self.rota(), rotulo)
        if chave not in indices and rotulo in rotulos:
            indices[chave] = rotulos.index(rotulo)
        self.pg.locator(sel).nth(indices.get(chave, 0)).click()
        self.pg.wait_for_timeout(300)
        self.pg.keyboard.press("Control+A")
        self.pg.keyboard.press("Backspace")
        self.pg.keyboard.type(valor, delay=15)
        self.pg.wait_for_timeout(300)

    def botao(self, texto: str, exato: bool = False):
        loc = self.pg.locator("flt-semantics[role=button]", has_text=re.compile(("^" + re.escape(texto) + "$") if exato else re.escape(texto)))
        loc.first.click()
        self.pg.wait_for_timeout(1200)
        self.semantica()

    def foto(self, nome: str) -> str:
        PASTA.mkdir(parents=True, exist_ok=True)
        self.pg.screenshot(path=str(PASTA / f"{nome}.png"))
        return f"evidencias/e2e/{nome}.png"

    def rota(self) -> str:
        return self.pg.evaluate("location.hash").lstrip("#")

    def fechar(self):
        self.ctx.close()


def rodar(s: Suite, nav, ctx) -> None:
    db, u, p = ctx["db"], ctx["usuarios"], ctx["postos"]
    ana = u["ana"]
    E = dict(severidade=MEDIA)

    def caso(aba, modulo, tela, tipo, cenario, passos, entrada, esperado, ok, obtido, evidencia="", sev=MEDIA, pre="Navegador Edge, app web ligado ao Supabase real"):
        s.check(bool(ok), obtido=obtido, aba=aba, modulo=modulo, tela=tela, tipo=tipo, cenario=cenario, precondicoes=pre,
                passos=passos, entrada=entrada, esperado=esperado, severidade=sev, evidencia=evidencia)

    def bloco_1():  # Mapa com dados reais
        a = App(nav)
        t0 = time.time()
        a.abrir("/", 3000)
        achou = False
        while time.time() - t0 < 30 and not achou:
            a.semantica()
            achou = a.pg.locator("flt-semantics[role=button]", has_text="R$").count() >= 5
            if not achou:
                a.pg.wait_for_timeout(1000)
        n = a.pg.locator("flt-semantics[role=button]", has_text="R$").count()
        caso("Integração", "Mapa", "Mapa", "Integração · app → banco", "Mapa abre em Fortaleza com pinos de preço reais",
             "Abrir o app com GPS em Fortaleza; esperar os pinos", "GPS -3,7627 / -38,5399", "Pelo menos 5 pinos com preço em até 30 s",
             achou, f"{n} pinos com preço em {time.time() - t0:.1f} s", a.foto("mapa_fortaleza"), ALTA)
        est = a.pg.locator("flt-semantics[role=button]", has_text="estimativa").count()
        caso("UI/Telas", "Mapa", "Mapa", "Acessibilidade · leitor de tela", "Pinos do mapa têm nome e preço legíveis por leitor de tela, com a marca de estimativa",
             "Ler a árvore de acessibilidade", "-", "Cada pino com nome do posto e preço; estimativas identificadas", n > 0,
             f"{n} pinos com rótulo; {est} marcados como estimativa", sev=BAIXA)
        a.fechar()

    def bloco_2():  # Busca
        a = App(nav)
        a.abrir("/buscar")
        a.campo("Nome, endereço, bairro, cidade ou UF", "itaitinga ce")
        ok = a.esperar_texto("Itaitinga", 15000)
        caso("Funcionais", "Busca", "Busca", "Funcional · positivo", "Busca por cidade e UF sem acento traz os postos da cidade",
             "Digitar 'itaitinga ce'", "itaitinga ce", "Lista com postos de Itaitinga", ok, "postos de Itaitinga na lista" if ok else a.texto()[:300],
             a.foto("busca_itaitinga"), ALTA)
        a.campo("Nome, endereço, bairro, cidade ou UF", "zzqxwy posto inexistente")
        ok = a.esperar_texto("Nenhum posto encontrado", 15000)
        caso("UI/Telas", "Busca", "Busca", "Estado vazio", "Busca sem resultado mostra o estado vazio", "Digitar texto sem correspondência",
             "zzqxwy posto inexistente", "Mensagem 'Nenhum posto encontrado'", ok, "estado vazio exibido" if ok else a.texto()[:300],
             a.foto("busca_vazia"), BAIXA)
        a.fechar()

    def bloco_3():  # Carregando: atrasa a resposta da busca em 5 s
        a = App(nav)
        a.abrir("/buscar")
        a.pg.route("**/rest/v1/rpc/buscar_postos*", lambda rota: (time.sleep(5), rota.continue_()))
        a.campo("Nome, endereço, bairro, cidade ou UF", "fortaleza")
        a.pg.wait_for_timeout(2000)
        a.semantica()
        durante = a.texto()
        ev = a.foto("busca_carregando")
        vazio_cedo = "Nenhum posto encontrado" in durante
        depois = a.esperar_texto("Fortaleza", 20000)
        caso("UI/Telas", "Busca", "Busca", "Estado de carregamento", "Enquanto a busca carrega, o app não mostra 'nenhum resultado' antes da hora",
             "Atrasar a resposta da API em 5 s; observar a tela aos 2 s e depois", "fortaleza",
             "Aos 2 s: indicador de carregamento, sem estado vazio; depois: resultados", (not vazio_cedo) and depois,
             f"aos 2 s mostrava estado vazio: {vazio_cedo}; resultados depois: {depois}", ev, MEDIA)
        a.fechar()

    def bloco_4():  # Sem internet
        a = App(nav)
        a.abrir("/buscar")
        a.ctx.set_offline(True)
        a.campo("Nome, endereço, bairro, cidade ou UF", "recife")
        ok = a.esperar_texto("Sem conexão", 15000)
        tem_botao = "Tentar de novo" in a.texto()
        ev = a.foto("busca_sem_internet")
        caso("UI/Telas", "Busca", "Busca", "Estado de erro", "Sem internet, a busca mostra mensagem clara e botão para tentar de novo",
             "Desligar a rede do navegador; buscar", "recife", "'Sem conexão com o servidor...' e botão 'Tentar de novo'", ok and tem_botao,
             f"mensagem: {ok}; botão: {tem_botao}", ev, ALTA)
        a.ctx.set_offline(False)
        if tem_botao:
            a.botao("Tentar de novo")
        ok = a.esperar_texto("Recife", 20000)
        caso("Performance", "Falha de serviço", "Busca", "Confiabilidade · recuperação", "Depois que a rede volta, 'Tentar de novo' carrega os resultados",
             "Religar a rede; tocar em Tentar de novo", "-", "Resultados de Recife", ok, "recuperou" if ok else a.texto()[:300], a.foto("busca_recuperada"), MEDIA)
        a.fechar()

    def bloco_5():  # Posto inexistente
        a = App(nav)
        a.abrir("/posto/999999999", 6000)
        ok = a.esperar_texto("não está mais disponível", 10000)
        caso("UI/Telas", "Posto", "Posto", "Estado de erro", "Posto inexistente mostra mensagem em vez de tela quebrada", "Abrir /posto/999999999",
             "id inexistente", "'Este posto não está mais disponível.'", ok, "mensagem exibida" if ok else a.texto()[:300], a.foto("posto_inexistente"), BAIXA)
        a.fechar()

    def bloco_6():  # Validações de formulário
        a = App(nav)
        a.abrir("/entrar")
        a.botao("Entrar", exato=True)
        ok = a.esperar_texto("Informe seu e-mail", 5000)
        caso("Autenticação", "Entrar", "Entrar", "Funcional · campos vazios", "Entrar com campos vazios mostra a validação", "Tocar em Entrar sem preencher",
             "-", "'Informe seu e-mail.'", ok, "validação exibida" if ok else a.texto()[:300], a.foto("entrar_vazio"), MEDIA)
        a.campo("E-mail", "abc")
        a.botao("Entrar", exato=True)
        ok = a.esperar_texto("E-mail inválido", 5000)
        caso("Autenticação", "Entrar", "Entrar", "Funcional · valor inválido", "E-mail sem @ é recusado na tela", "Digitar 'abc' e tocar em Entrar",
             "abc", "'E-mail inválido.'", ok, "validação exibida" if ok else a.texto()[:300], sev=BAIXA)
        a.fechar()
        # Tela nova a cada cenário: no Flutter web o preenchimento automático não substitui texto já digitado
        a = App(nav)
        a.abrir("/entrar")
        a.campo("E-mail", ana["email"])
        a.campo("Senha", "SenhaErrada123")
        a.botao("Entrar", exato=True)
        a.esperar_texto("incorret", 8000)
        txt = a.texto()
        ok = bool(re.search(r"incorret|inválid|errad", txt, re.I)) and a.rota() == "/entrar"
        caso("Autenticação", "Entrar", "Entrar", "Funcional · negativo", "Senha errada mostra mensagem em português e não entra",
             "Preencher e-mail válido e senha errada", "senha errada", "Mensagem de erro clara; continua em Entrar", ok,
             re.search(r"[^.]*(incorret|inválid|errad)[^.]*\.?", txt, re.I).group(0)[:200] if re.search(r"(incorret|inválid|errad)", txt, re.I) else txt[:300],
             a.foto("entrar_senha_errada"), ALTA)
        a.fechar()

        a = App(nav)
        a.abrir("/cadastro")
        a.botao("Criar conta", exato=True)
        ok = a.esperar_texto("Informe seu nome", 5000)
        caso("Autenticação", "Criar conta", "Criar conta", "Funcional · campos vazios", "Cadastro vazio mostra a validação do nome",
             "Tocar em Criar conta sem preencher", "-", "'Informe seu nome.'", ok, "validação exibida" if ok else a.texto()[:300], sev=MEDIA)
        a.fechar()

        def cadastro(senha, confirmacao):
            c = App(nav)
            c.abrir("/cadastro")
            c.campo("Nome", "Teste Auditoria")
            c.campo("E-mail", "teste@" + dt.DOMINIO)
            c.campo("Senha", senha)
            c.campo("Confirme a senha", confirmacao)
            c.botao("Criar conta", exato=True)
            return c

        for senha, msg in (("abc", "Use pelo menos 8 caracteres"), ("abcdefgh", "Use letras e números")):
            c = cadastro(senha, senha)
            ok = c.esperar_texto(msg, 5000)
            caso("Autenticação", "Criar conta", "Criar conta", "Funcional · valor inválido", f"Senha '{senha}' é recusada na tela",
                 "Preencher o cadastro com a senha", senha, f"'{msg}.'", ok, "validação exibida" if ok else c.texto()[:300], sev=MEDIA)
            c.fechar()
        c = cadastro("Senha1234", "Senha9999")
        ok = c.esperar_texto("As senhas não conferem", 5000)
        caso("Autenticação", "Criar conta", "Criar conta", "Funcional · valor inválido", "Confirmação de senha diferente é recusada",
             "Senha e confirmação diferentes", "Senha1234 / Senha9999", "'As senhas não conferem.'", ok,
             "validação exibida" if ok else c.texto()[:300], c.foto("cadastro_senhas_diferentes"), MEDIA)
        c.fechar()
        c = cadastro("Senha1234", "Senha1234")
        aviso = c.esperar_texto("aceite os termos", 4000)
        ev = c.foto("cadastro_sem_termos")
        criado = db.execute("select count(*) from auth.users where email = %s", ("teste@" + dt.DOMINIO,)).fetchone()[0]
        caso("Autenticação", "Criar conta", "Criar conta", "Funcional · regra", "Cadastro exige aceitar os termos de uso",
             "Preencher tudo certo sem marcar os termos; tocar em Criar conta", "termos desmarcados",
             "Aviso 'aceite os termos de uso...'; continua em Criar conta; nenhuma conta criada",
             aviso and c.rota() == "/cadastro" and criado == 0, f"aviso: {aviso}; rota {c.rota()}; contas criadas: {criado}", ev, MEDIA)
        c.fechar()

    def bloco_7():  # Recuperar senha (e-mail inexistente: não envia nada)
        a = App(nav)
        a.abrir("/recuperar-senha")
        a.campo("E-mail", "ninguem@" + dt.DOMINIO)
        a.botao("Enviar link")
        a.pg.wait_for_timeout(3000)
        a.semantica()
        txt = a.texto()
        ok = bool(re.search(r"enviamos|verifique|link", txt, re.I)) and not re.search(r"não encontrad|inexistente", txt, re.I)
        caso("Autenticação", "Recuperar senha", "Recuperar senha", "Segurança · enumeração",
             "Recuperação para e-mail sem conta responde igual a uma conta existente", "Informar e-mail sem conta; tocar em Enviar link",
             "e-mail inexistente", "Mensagem genérica de envio, sem dizer que a conta não existe", ok, txt[:300], a.foto("recuperar_senha"), BAIXA)
        a.fechar()

    def bloco_8():  # Rota protegida
        a = App(nav)
        a.abrir("/pontos")
        caso("Autenticação", "Rotas protegidas", "Meus pontos", "Segurança · navegação", "Visitante que abre Meus pontos pela URL vai para Entrar",
             "Abrir #/pontos sem login", "-", "Rota /entrar", a.rota() == "/entrar", f"rota final {a.rota()}", sev=ALTA)
        a.fechar()

    def bloco_9():  # Login real e fluxos logados
        a = App(nav)
        a.abrir("/entrar")
        a.campo("E-mail", ana["email"])
        a.campo("Senha", ana["senha"])
        t0 = time.time()
        a.botao("Entrar", exato=True)
        ok = a.esperar_texto("Auditoria Ana", 15000)
        caso("Autenticação", "Entrar", "Entrar → Perfil", "Funcional · positivo", "Login pela tela com conta confirmada abre o perfil com o nome",
             "Preencher e-mail e senha; tocar em Entrar", "credenciais válidas", "Perfil com o nome 'Auditoria Ana'", ok,
             f"rota {a.rota()} em {time.time() - t0:.1f} s", a.foto("login_ok"), CRITICA)
        a.pg.reload()
        a.pg.wait_for_selector("flutter-view", timeout=60000)
        a.pg.wait_for_timeout(5000)
        a.semantica()
        a.abrir("/perfil")
        ok = a.esperar_texto("Auditoria Ana", 10000)
        caso("Autenticação", "Sessão", "Perfil", "Funcional · sessão", "Sessão continua depois de recarregar o app", "Recarregar a página logado",
             "-", "Continua logado", ok, "continua logado" if ok else a.texto()[:300], sev=ALTA)

        a.abrir(f"/posto/{p['exata']}", 6000)
        ok_posto = a.esperar_texto("Auditoria Exata", 10000)
        a.botao("Salvar nos favoritos")
        a.pg.wait_for_timeout(2000)
        fav = db.execute("select count(*) from public.favoritos where usuario_id=%s and posto_id=%s", (ana["id"], p["exata"])).fetchone()[0]
        caso("Funcionais", "Favoritos", "Posto", "Funcional · positivo", "Favoritar pelo coração grava o favorito na conta",
             "Abrir o posto de teste; tocar em Salvar nos favoritos", "-", "1 favorito no banco", ok_posto and fav == 1,
             f"posto aberto: {ok_posto}; favoritos no banco: {fav}", a.foto("posto_favoritado"), MEDIA)
        a.abrir("/favoritos", 5000)
        ok = a.esperar_texto("Auditoria Exata", 10000)
        caso("Funcionais", "Favoritos", "Favoritos", "Integração · app → banco", "Aba Favoritos lista o posto favoritado", "Abrir Favoritos",
             "-", "Posto de teste na lista", ok, "listado" if ok else a.texto()[:300], a.foto("favoritos_lista"), MEDIA)

        a.abrir(f"/posto/{p['exata']}/avaliar", 5000)
        a.botao("4 estrelas", exato=True)
        a.campo("Comentário (opcional)", "Avaliação de teste da auditoria pela tela")
        a.botao("Publicar avaliação")
        a.pg.wait_for_timeout(2500)
        av = db.execute("select nota, comentario from public.avaliacoes where usuario_id=%s and posto_id=%s", (ana["id"], p["exata"])).fetchone()
        caso("Funcionais", "Avaliações", "Avaliar", "Funcional · positivo", "Avaliar pela tela grava nota e comentário",
             "Abrir Avaliar; tocar na 4ª estrela; escrever; publicar", "4 estrelas e comentário", "Avaliação com nota 4 no banco",
             av is not None and av[0] == 4, f"no banco: {av}", a.foto("avaliacao_publicada"), MEDIA)

        a.abrir("/perfil", 5000)
        if a.pg.locator("flt-semantics[role=button]", has_text="Sair").count():
            a.botao("Sair")
            for confirma in ("Sair", "Confirmar"):
                if a.pg.locator("flt-semantics[role=button]", has_text=confirma).count():
                    a.botao(confirma)
                    break
        ok = a.esperar_texto("Contribua com a sua cidade", 10000)
        caso("Autenticação", "Sair", "Perfil", "Funcional · positivo", "Sair volta o perfil para o modo visitante", "Perfil → Sair",
             "-", "Perfil mostra o convite para criar conta", ok, "visitante" if ok else a.texto()[:300], a.foto("logout"), ALTA)
        a.fechar()

    for f, titulo in [(bloco_1, 'Mapa com dados reais'), (bloco_2, 'Busca'), (bloco_3, 'Carregando: atrasa a resposta da busca em 5 s'), (bloco_4, 'Sem internet'), (bloco_5, 'Posto inexistente'), (bloco_6, 'Validações de formulário'), (bloco_7, 'Recuperar senha (e-mail inexistente: não envia nada)'), (bloco_8, 'Rota protegida'), (bloco_9, 'Login real e fluxos logados')]:
        try:
            f()
        except Exception as e:  # noqa: BLE001
            s.add(status="BLOCKED", aba="Integração", modulo="Execução E2E", tela=titulo, tipo="Execução",
                  cenario=f"Bloco '{titulo}' interrompido antes do fim", precondicoes="-", passos="-", entrada="-",
                  esperado="Bloco completo", obtido=f"{type(e).__name__}: {str(e)[:300]}", severidade=MEDIA,
                  obs="Os cenários seguintes deste bloco não rodaram.")

    s.add(status="NOT TESTED", aba="Funcionais", modulo="Envio por foto", tela="Enviar preços", tipo="Funcional · positivo",
          cenario="Fotografar painel real, revisar e enviar", precondicoes="Celular Android no posto",
          passos="Abrir posto → Atualizar preço → fotografar → revisar → enviar", entrada="foto de painel real",
          esperado="Valores lidos corretamente e envio aceito", obtido="Não executado no navegador: a leitura do painel usa o ML Kit, que só roda em Android e iOS.",
          severidade=CRITICA, obs="Teste da aba Android.")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    s = Suite("e2e", "E")
    db = comum.conectar_banco()
    print(dt.limpar(db))
    ctx = {"db": db}
    try:
        ctx["postos"] = dt.criar_postos(db)
        ctx["usuarios"] = dt.criar_usuarios(db)
        with sync_playwright() as pw:
            nav = pw.chromium.launch(channel="msedge", headless=True, args=ARGS)
            try:
                rodar(s, nav, ctx)
            except Exception as e:  # noqa: BLE001
                import traceback
                traceback.print_exc()
                s.add(status="BLOCKED", aba="Integração", modulo="Execução", tela="E2E", tipo="Execução",
                      cenario="Sequência de ponta a ponta interrompida", precondicoes="-", passos="-", entrada="-",
                      esperado="Sequência completa", obtido=f"{type(e).__name__}: {str(e)[:300]}", severidade=MEDIA,
                      obs="Os cenários seguintes desta sequência não rodaram.")
            nav.close()
    finally:
        print(dt.limpar(db))
        s.salvar()
    return 0


if __name__ == "__main__":
    sys.exit(main())
