"""
Autenticação, autorização entre usuários e Edge Functions, contra o projeto real com os dados da auditoria.
"""
from __future__ import annotations

import base64
import concurrent.futures as cf
import json
import math
import time

import dados_teste as dt
from comum import ALTA, BAIXA, CRITICA, MEDIA, http, resumo

F_ENVIAR, F_POSICAO, F_EXCLUIR, F_SINC = (f"/functions/v1/{n}" for n in
                                          ("enviar-precos", "corrigir-posicao", "excluir-conta", "sincronizar-cadastro-anp"))


def deslocar(lat: float, lon: float, metros_norte: float, metros_leste: float = 0) -> tuple[float, float]:
    return lat + metros_norte / 111320, lon + metros_leste / (111320 * math.cos(math.radians(lat)))


def um(db, sql, *args):
    r = db.execute(sql, args).fetchone()
    return r[0] if r else None


# ------------------------------------------------------------------ autenticação
def autenticacao(s, ctx) -> None:
    u = ctx["usuarios"]
    A = dict(aba="Autenticação", modulo="Autenticação")

    r = dt.entrar(u["ana"]["email"], u["ana"]["senha"])
    ok = r.status == 200 and isinstance(r.corpo, dict) and r.corpo.get("access_token")
    s.check(bool(ok), obtido=f"HTTP {r.status} em {r.ms} ms; token recebido: {bool(ok)}", **A, tela="Entrar", tipo="Funcional · positivo",
            cenario="Login com e-mail e senha corretos", precondicoes="Usuária de teste com e-mail confirmado",
            passos="POST /auth/v1/token?grant_type=password", entrada="e-mail e senha válidos",
            esperado="HTTP 200 com access_token e refresh_token", severidade=CRITICA)
    for nome in dt.USUARIOS:
        if nome == "nao_confirmado":
            continue
        rr = dt.entrar(u[nome]["email"], u[nome]["senha"])
        if rr.status == 200:
            u[nome]["token"] = rr.corpo["access_token"]
            u[nome]["refresh"] = rr.corpo["refresh_token"]

    r = dt.entrar(u["ana"]["email"], "senha-errada-123")
    s.check(r.status == 400 and "invalid" in r.texto.lower(), obtido=resumo(r), **A, tela="Entrar", tipo="Funcional · negativo",
            cenario="Login com senha errada", precondicoes="Usuária existente", passos="POST /auth/v1/token com senha errada",
            entrada="senha incorreta", esperado="HTTP 400 invalid_credentials, sem token", severidade=CRITICA)
    r2 = dt.entrar("ninguem.existe@" + dt.DOMINIO, "senha-errada-123")
    s.check(r2.status == r.status and r2.corpo.get("error_code") == (r.corpo or {}).get("error_code"),
            obtido=f"existente: {resumo(r, 120)} | inexistente: {resumo(r2, 120)}", **A, tela="Entrar", tipo="Segurança · enumeração",
            cenario="E-mail inexistente recebe a mesma resposta que senha errada (não revela quem tem conta)",
            precondicoes="-", passos="Comparar as duas respostas", entrada="e-mail inexistente", esperado="Mesma resposta e mesmo código",
            severidade=MEDIA)
    r = dt.entrar(u["nao_confirmado"]["email"], u["nao_confirmado"]["senha"])
    s.check(r.status == 400 and "confirm" in r.texto.lower(), obtido=resumo(r), **A, tela="Entrar", tipo="Funcional · negativo",
            cenario="Login de conta com e-mail ainda não confirmado é recusado", precondicoes="Usuário criado sem confirmação",
            passos="POST /auth/v1/token", entrada="credenciais corretas", esperado="HTTP 400 email_not_confirmed", severidade=ALTA)
    for desc, corpo in (("e-mail e senha vazios", {"email": "", "password": ""}), ("sem senha", {"email": u["ana"]["email"]})):
        r = http("POST", "/auth/v1/token?grant_type=password", corpo)
        s.check(r.status in (400, 422), obtido=resumo(r), **A, tela="Entrar", tipo="Funcional · campos vazios",
                cenario=f"Login com {desc}", precondicoes="-", passos="POST /auth/v1/token", entrada=json.dumps(corpo),
                esperado="HTTP 400/422 sem token", severidade=MEDIA)

    # Cadastro: política de senha no servidor
    for senha, esp in (("1", "recusada"), ("abc12", "recusada")):
        r = http("POST", "/auth/v1/signup", {"email": f"senha.fraca.{senha}@{dt.DOMINIO}", "password": senha})
        s.check(r.status in (400, 422) and "weak" in r.texto.lower(), obtido=resumo(r), **A, tela="Criar conta",
                tipo="Segurança · política de senha", cenario=f"Cadastro com senha de {len(senha)} caractere(s) é recusado pelo servidor",
                precondicoes="-", passos="POST /auth/v1/signup", entrada=f"senha '{senha}'", esperado="HTTP 422 weak_password",
                severidade=MEDIA)
    # A regra do app (8+ caracteres, letras e números) também vale no servidor? Testado pela troca de senha,
    # que passa pela mesma validação do cadastro e não dispara e-mail.
    for senha, desc in (("abc123", "6 caracteres"), ("abcdefgh", "8 letras e nenhum número")):
        r = http("PUT", "/auth/v1/user", {"password": senha}, token=u["bruno"]["token"])
        aceitou = r.status == 200
        s.check(not aceitou, obtido=resumo(r, 300), **A, tela="Criar conta / Alterar senha", tipo="Segurança · política de senha",
                cenario=f"Servidor recusa senha com {desc}, que o app recusa",
                precondicoes="Regra do app: pelo menos 8 caracteres, com letras e números; bruno logado",
                passos="PUT /auth/v1/user {password} (mesma validação do cadastro)", entrada=f"'{senha}'",
                esperado="HTTP 422 weak_password", severidade=MEDIA,
                obs="Se o servidor aceitar, a regra existe só na tela do app e qualquer chamada direta à API cria senhas mais fracas.")
        if aceitou:
            http("PUT", "/auth/v1/user", {"password": u["bruno"]["senha"]}, token=u["bruno"]["token"])
    r = http("POST", "/auth/v1/signup", {"email": f"cadastro.novo@{dt.DOMINIO}", "password": "Senha1234", "data": {"nome": "Cadastro Novo"}})
    s.check(r.status in (400, 422) and "invalid" in r.texto.lower(), obtido=resumo(r, 300), **A, tela="Criar conta",
            tipo="Funcional · validação", cenario="Cadastro com e-mail de domínio inexistente é recusado pelo servidor",
            precondicoes="-", passos="POST /auth/v1/signup", entrada=f"cadastro.novo@{dt.DOMINIO} (domínio .test, sem servidor de e-mail)",
            esperado="HTTP 400 email_address_invalid", severidade=BAIXA)
    s.add(status="NOT TESTED", obtido="Não executado: exige uma caixa de e-mail real; cadastrar endereço de terceiros enviaria e-mail a eles.",
          **A, tela="Criar conta", tipo="Integração · e-mail",
          cenario="E-mail de confirmação chega a um endereço que não é membro do projeto no Supabase",
          precondicoes="App instalado; e-mail pessoal que não seja o dono do projeto", passos="Criar conta no app; abrir o e-mail; tocar no link",
          entrada="e-mail real", esperado="E-mail chega em minutos; o link confirma e o app entra",
          severidade=CRITICA, obs="Teste do Android. O SMTP padrão do Supabase tem limite baixo por hora e pode restringir destinatários; "
                                  "se o e-mail não chegar, é preciso configurar SMTP próprio antes de lançar.")
    r = http("POST", "/auth/v1/signup", {"email": u["ana"]["email"], "password": "OutraSenha123"})
    revela = r.status in (400, 422) and "already" in r.texto.lower()
    s.check(not revela, obtido=resumo(r, 300), **A, tela="Criar conta", tipo="Segurança · enumeração",
            cenario="Cadastro com e-mail já usado não revela que a conta existe", precondicoes="Conta ana existente",
            passos="POST /auth/v1/signup com e-mail existente", entrada="e-mail já cadastrado",
            esperado="Resposta igual a de um cadastro novo (proteção contra enumeração do Supabase)", severidade=BAIXA)

    # Sessão
    tok = u["ana"]["token"]
    partes = tok.split(".")
    carga = json.loads(base64.urlsafe_b64decode(partes[1] + "=" * (-len(partes[1]) % 4)))
    dur = carga.get("exp", 0) - carga.get("iat", 0)
    s.check(0 < dur <= 3600, obtido=f"validade do token: {dur} s; papel: {carga.get('role')}", **A, tela="Sessão",
            tipo="Segurança · sessão", cenario="Token de acesso expira em até 1 hora", precondicoes="Login feito",
            passos="Decodificar o JWT e comparar exp e iat", entrada="access_token", esperado="Validade entre 0 e 3600 s",
            severidade=MEDIA)
    r = http("POST", "/auth/v1/token?grant_type=refresh_token", {"refresh_token": u["ana"]["refresh"]})
    novo = r.corpo.get("access_token") if isinstance(r.corpo, dict) else None
    s.check(r.status == 200 and bool(novo), obtido=resumo(r, 80), **A, tela="Sessão", tipo="Funcional · sessão",
            cenario="Renovação da sessão com refresh token", precondicoes="Login feito", passos="POST /auth/v1/token?grant_type=refresh_token",
            entrada="refresh_token", esperado="HTTP 200 com novo access_token", severidade=ALTA)
    if novo:
        u["ana"]["token"], u["ana"]["refresh"] = novo, r.corpo["refresh_token"]
    adulterado = partes[0] + "." + partes[1] + "." + partes[2][:-4] + ("AAAA" if not partes[2].endswith("AAAA") else "BBBB")
    r = http("POST", "/rest/v1/rpc/meu_resumo", {}, token=adulterado)
    s.check(r.status == 401, obtido=resumo(r, 200), **A, tela="Sessão", tipo="Segurança · token",
            cenario="Token com assinatura adulterada é recusado pela API do banco", precondicoes="-",
            passos="POST /rest/v1/rpc/meu_resumo com JWT alterado", entrada="JWT com assinatura trocada", esperado="HTTP 401",
            severidade=CRITICA)
    for nome, f in (("enviar-precos", F_ENVIAR), ("corrigir-posicao", F_POSICAO), ("excluir-conta", F_EXCLUIR)):
        r = http("POST", f, {}, token=adulterado)
        s.check(r.status == 401, obtido=resumo(r, 200), aba="Edge Functions", modulo=nome, tela=nome, tipo="Segurança · token",
                cenario=f"{nome} recusa token adulterado", precondicoes="-", passos=f"POST {f} com JWT alterado",
                entrada="JWT com assinatura trocada", esperado="HTTP 401", severidade=CRITICA)

    # Troca de senha
    nova = "N0va-" + u["carla"]["senha"][-10:]
    r = http("PUT", "/auth/v1/user", {"password": nova}, token=u["carla"]["token"])
    ok_troca = r.status == 200
    r_velha = dt.entrar(u["carla"]["email"], u["carla"]["senha"])
    r_nova = dt.entrar(u["carla"]["email"], nova)
    s.check(ok_troca and r_velha.status == 400 and r_nova.status == 200,
            obtido=f"troca HTTP {r.status}; login com a antiga HTTP {r_velha.status}; com a nova HTTP {r_nova.status}", **A,
            tela="Alterar senha", tipo="Funcional · positivo", cenario="Troca de senha: a antiga deixa de funcionar e a nova entra",
            precondicoes="Usuária carla logada", passos="PUT /auth/v1/user {password}; login com a antiga; login com a nova",
            entrada="senha nova válida", esperado="200; 400; 200", severidade=ALTA)
    if r_nova.status == 200:
        u["carla"]["senha"] = nova
        u["carla"]["token"], u["carla"]["refresh"] = r_nova.corpo["access_token"], r_nova.corpo["refresh_token"]

    # Recuperação de senha (e-mail inexistente: não dispara e-mail)
    r = http("POST", "/auth/v1/recover", {"email": "ninguem.existe@" + dt.DOMINIO})
    s.check(r.status == 200, obtido=resumo(r, 200), **A, tela="Recuperar senha", tipo="Segurança · enumeração",
            cenario="Recuperação de senha para e-mail inexistente responde igual (não revela contas)", precondicoes="-",
            passos="POST /auth/v1/recover", entrada="e-mail inexistente", esperado="HTTP 200", severidade=BAIXA)
    s.add(status="NOT TESTED", obtido="Não executado: enviaria um e-mail real e gastaria o limite do SMTP padrão.", **A,
          tela="Recuperar senha", tipo="Funcional · positivo", cenario="Link de recuperação chega ao e-mail e abre a tela Nova senha no app",
          precondicoes="Conta com e-mail real; app instalado", passos="Pedir recuperação; abrir o e-mail no celular; tocar no link",
          entrada="e-mail real", esperado="O app abre em Nova senha e aceita a senha nova", severidade=ALTA,
          obs="Testar no Android (aba Android). O link usa br.com.gasprice.app://auth-callback.")

    # Logout
    r = http("POST", "/auth/v1/logout", {}, token=u["bloqueado"]["token"])
    r_ref = http("POST", "/auth/v1/token?grant_type=refresh_token", {"refresh_token": u["bloqueado"]["refresh"]})
    s.check(r.status in (200, 204) and r_ref.status in (400, 401), obtido=f"logout HTTP {r.status}; refresh depois HTTP {r_ref.status}",
            **A, tela="Perfil · Sair", tipo="Funcional · positivo", cenario="Sair encerra a sessão: o refresh token deixa de valer",
            precondicoes="Usuário logado", passos="POST /auth/v1/logout; tentar renovar a sessão", entrada="token do usuário",
            esperado="Logout 204; renovação recusada", severidade=ALTA)
    r_acc = http("POST", "/rest/v1/rpc/meu_resumo", {}, token=u["bloqueado"]["token"])
    s.add(status="PASS", obtido=f"API do banco com o access token antigo depois do logout: HTTP {r_acc.status}", **A,
          tela="Sessão", tipo="Segurança · sessão", cenario="Access token emitido antes do logout, até expirar",
          precondicoes="Logout feito", passos="Chamar meu_resumo com o access token antigo", entrada="token antigo",
          esperado="Comportamento conhecido do JWT: continua válido até expirar (no máximo 1 h)", severidade=BAIXA,
          obs="Informativo. O app descarta o token ao sair; o risco é só de token copiado antes do logout.")
    rr = dt.entrar(u["bloqueado"]["email"], u["bloqueado"]["senha"])
    if rr.status == 200:
        u["bloqueado"]["token"] = rr.corpo["access_token"]


# ------------------------------------------------------------------ autorização entre usuários
def autorizacao(s, ctx) -> None:
    db, u, p = ctx["db"], ctx["usuarios"], ctx["postos"]
    ana, bruno = u["ana"], u["bruno"]
    Z = dict(aba="Segurança", modulo="Autorização entre usuários")

    # Avaliações
    r = http("POST", "/rest/v1/avaliacoes", {"posto_id": p["exata"], "usuario_id": ana["id"], "nota": 4, "comentario": "Avaliação de teste da auditoria"},
             token=ana["token"], cabecalhos={"Prefer": "return=representation"})
    av_id = r.corpo[0]["id"] if r.status == 201 and isinstance(r.corpo, list) else None
    s.check(av_id is not None, obtido=resumo(r, 200), aba="Funcionais", modulo="Avaliações", tela="Avaliar", tipo="Funcional · positivo",
            cenario="Usuária logada cria a própria avaliação", precondicoes="ana logada", passos="POST /rest/v1/avaliacoes",
            entrada="nota 4 e comentário", esperado="HTTP 201", severidade=ALTA)
    ctx["avaliacao_ana"] = av_id
    media = db.execute("select nota_media, total_avaliacoes from public.postos where id=%s", (p["exata"],)).fetchone()
    s.check(media and float(media[0] or 0) == 4.0 and media[1] == 1, obtido=f"nota_media={media[0]}, total={media[1]}",
            aba="Banco de Dados", modulo="Avaliações", tela="Gatilho recalcular_nota_posto", tipo="Banco · regra de negócio",
            cenario="Nota média e total do posto recalculados ao criar avaliação", precondicoes="Avaliação criada",
            passos="Ler postos.nota_media e total_avaliacoes", entrada="nota 4", esperado="4,00 e 1", severidade=ALTA)
    r = http("PATCH", f"/rest/v1/avaliacoes?id=eq.{av_id}", {"nota": 0, "comentario": "alterado por outro"}, token=bruno["token"],
             cabecalhos={"Prefer": "return=representation"})
    nota = um(db, "select nota from public.avaliacoes where id=%s", av_id)
    s.check(nota == 4, obtido=f"{resumo(r, 120)}; nota no banco: {nota}", **Z, tela="Avaliações", tipo="Segurança · IDOR",
            cenario="Usuário não altera a avaliação de outra pessoa", precondicoes="Avaliação da ana; bruno logado",
            passos="PATCH /rest/v1/avaliacoes?id=eq.<id da ana> com token do bruno", entrada="nota 0", esperado="Nenhuma alteração",
            severidade=CRITICA)
    r = http("DELETE", f"/rest/v1/avaliacoes?id=eq.{av_id}", token=bruno["token"])
    existe = um(db, "select count(*) from public.avaliacoes where id=%s", av_id)
    s.check(existe == 1, obtido=f"{resumo(r, 120)}; avaliação ainda existe: {existe == 1}", **Z, tela="Avaliações", tipo="Segurança · IDOR",
            cenario="Usuário não apaga a avaliação de outra pessoa", precondicoes="Avaliação da ana", passos="DELETE com token do bruno",
            entrada=f"id {av_id}", esperado="Avaliação continua no banco", severidade=CRITICA)
    r = http("POST", "/rest/v1/avaliacoes", {"posto_id": p["rua"], "usuario_id": ana["id"], "nota": 0}, token=bruno["token"])
    s.check(r.status in (401, 403), obtido=resumo(r, 200), **Z, tela="Avaliar", tipo="Segurança · falsificação",
            cenario="Usuário não cria avaliação em nome de outra pessoa", precondicoes="bruno logado",
            passos="POST /rest/v1/avaliacoes com usuario_id da ana", entrada="usuario_id de outra pessoa", esperado="HTTP 401/403",
            severidade=CRITICA)
    r = http("PATCH", f"/rest/v1/avaliacoes?id=eq.{av_id}", {"votos_uteis": 999}, token=ana["token"])
    votos = um(db, "select votos_uteis from public.avaliacoes where id=%s", av_id)
    s.check(r.status in (400, 401, 403) and votos == 0, obtido=f"{resumo(r, 160)}; votos_uteis={votos}", **Z, tela="Avaliações",
            tipo="Segurança · coluna protegida", cenario="Autora não altera o contador de votos úteis da própria avaliação",
            precondicoes="ana logada", passos="PATCH votos_uteis", entrada="999", esperado="Recusado; contador continua 0", severidade=ALTA)
    for desc, corpo, sev in (("nota 6", {"nota": 6}, MEDIA), ("nota -1", {"nota": -1}, MEDIA),
                             ("comentário de 2 caracteres", {"nota": 3, "comentario": "ok"}, BAIXA),
                             ("comentário de 501 caracteres", {"nota": 3, "comentario": "x" * 501}, BAIXA)):
        r = http("POST", "/rest/v1/avaliacoes", {"posto_id": p["rua"], "usuario_id": bruno["id"], **corpo}, token=bruno["token"])
        s.check(r.status == 400, obtido=resumo(r, 200), aba="Banco de Dados", modulo="Avaliações", tela="Avaliar",
                tipo="Banco · validação", cenario=f"Avaliação com {desc} é recusada pelo banco", precondicoes="bruno logado",
                passos="POST /rest/v1/avaliacoes", entrada=desc, esperado="HTTP 400 (restrição check)", severidade=sev)
    r = http("POST", "/rest/v1/avaliacoes", {"posto_id": p["exata"], "usuario_id": ana["id"], "nota": 2}, token=ana["token"])
    s.check(r.status == 409, obtido=resumo(r, 200), aba="Banco de Dados", modulo="Avaliações", tela="Avaliar", tipo="Banco · unicidade",
            cenario="Segunda avaliação da mesma pessoa no mesmo posto é recusada", precondicoes="ana já avaliou o posto",
            passos="POST outra avaliação", entrada="nota 2", esperado="HTTP 409 (uma por pessoa e posto)", severidade=MEDIA)
    for nome in ("banido", "bloqueado"):
        r = http("POST", "/rest/v1/avaliacoes", {"posto_id": p["exata"], "usuario_id": u[nome]["id"], "nota": 5}, token=u[nome]["token"])
        s.check(r.status in (401, 403), obtido=resumo(r, 200), **Z, tela="Avaliar", tipo="Segurança · conta suspensa",
                cenario=f"Usuário {nome} não consegue avaliar", precondicoes=f"perfil {nome}", passos="POST /rest/v1/avaliacoes",
                entrada="nota 5", esperado="HTTP 401/403 (usuario_pode_contribuir)", severidade=ALTA)

    # Votos
    r = http("POST", "/rest/v1/avaliacao_votos", {"avaliacao_id": av_id, "usuario_id": bruno["id"]}, token=bruno["token"])
    votos = um(db, "select votos_uteis from public.avaliacoes where id=%s", av_id)
    s.check(r.status == 201 and votos == 1, obtido=f"{resumo(r, 100)}; votos_uteis={votos}", aba="Funcionais", modulo="Avaliações",
            tela="Avaliações · útil", tipo="Funcional · positivo", cenario="Voto útil de outra pessoa conta no contador",
            precondicoes="Avaliação da ana; bruno logado", passos="POST /rest/v1/avaliacao_votos", entrada="voto do bruno",
            esperado="HTTP 201 e votos_uteis = 1", severidade=MEDIA)
    r = http("POST", "/rest/v1/avaliacao_votos", {"avaliacao_id": av_id, "usuario_id": u["carla"]["id"]}, token=bruno["token"])
    s.check(r.status in (401, 403), obtido=resumo(r, 160), **Z, tela="Avaliações · útil", tipo="Segurança · falsificação",
            cenario="Usuário não vota em nome de outra pessoa", precondicoes="bruno logado", passos="POST voto com usuario_id da carla",
            entrada="usuario_id de outra pessoa", esperado="HTTP 401/403", severidade=ALTA)
    r = http("POST", "/rest/v1/avaliacao_votos", {"avaliacao_id": av_id, "usuario_id": ana["id"]}, token=ana["token"])
    s.check(r.status in (400, 401, 403), obtido=resumo(r, 160), aba="Funcionais", modulo="Avaliações", tela="Avaliações · útil",
            tipo="Regra de negócio · servidor", cenario="Autora não consegue votar na própria avaliação pela API",
            precondicoes="ana logada", passos="POST voto da ana na própria avaliação", entrada="-",
            esperado="Recusado no servidor (regra RN: não votar na própria avaliação)", severidade=BAIXA,
            obs="O app esconde o botão; aqui se confere se o servidor também impede.")
    if r.status == 201:
        db.execute("delete from public.avaliacao_votos where avaliacao_id=%s and usuario_id=%s", (av_id, ana["id"]))
    r = http("POST", "/rest/v1/avaliacao_votos", {"avaliacao_id": av_id, "usuario_id": bruno["id"]}, token=bruno["token"])
    s.check(r.status == 409, obtido=resumo(r, 120), aba="Banco de Dados", modulo="Avaliações", tela="Avaliações · útil",
            tipo="Banco · unicidade", cenario="Mesmo usuário não vota duas vezes", precondicoes="bruno já votou",
            passos="POST o mesmo voto de novo", entrada="-", esperado="HTTP 409", severidade=MEDIA)

    # Favoritos
    r = http("POST", "/rest/v1/favoritos", {"usuario_id": ana["id"], "posto_id": p["exata"]}, token=ana["token"])
    s.check(r.status == 201, obtido=resumo(r, 120), aba="Funcionais", modulo="Favoritos", tela="Favoritos", tipo="Funcional · positivo",
            cenario="Usuária favorita um posto", precondicoes="ana logada", passos="POST /rest/v1/favoritos", entrada="posto de teste",
            esperado="HTTP 201", severidade=MEDIA)
    r = http("GET", "/rest/v1/favoritos?select=*", token=bruno["token"])
    s.check(r.status == 200 and r.corpo == [], obtido=resumo(r, 160), **Z, tela="Favoritos", tipo="Segurança · IDOR",
            cenario="Usuário não vê os favoritos de outra pessoa", precondicoes="ana tem 1 favorito; bruno nenhum",
            passos="GET /rest/v1/favoritos com token do bruno", entrada="-", esperado="Lista vazia", severidade=ALTA)
    r = http("DELETE", f"/rest/v1/favoritos?usuario_id=eq.{ana['id']}", token=bruno["token"])
    n = um(db, "select count(*) from public.favoritos where usuario_id=%s", ana["id"])
    s.check(n == 1, obtido=f"{resumo(r, 100)}; favoritos da ana: {n}", **Z, tela="Favoritos", tipo="Segurança · IDOR",
            cenario="Usuário não apaga favoritos de outra pessoa", precondicoes="ana tem 1 favorito", passos="DELETE com token do bruno",
            entrada="usuario_id da ana", esperado="Favorito continua", severidade=ALTA)
    r = http("POST", "/rest/v1/favoritos", {"usuario_id": ana["id"], "posto_id": p["rua"]}, token=bruno["token"])
    s.check(r.status in (401, 403), obtido=resumo(r, 160), **Z, tela="Favoritos", tipo="Segurança · falsificação",
            cenario="Usuário não cria favorito para outra pessoa", precondicoes="bruno logado", passos="POST com usuario_id da ana",
            entrada="-", esperado="HTTP 401/403", severidade=MEDIA)
    r = http("POST", "/rest/v1/rpc/meus_favoritos", {}, token=ana["token"])
    s.check(r.status == 200 and isinstance(r.corpo, list) and len(r.corpo) == 1 and r.corpo[0].get("id") == p["exata"],
            obtido=resumo(r, 200), aba="Backend/API", modulo="Favoritos", tela="rpc/meus_favoritos", tipo="Funcional · contrato",
            cenario="meus_favoritos devolve o posto favoritado com preços e precisão", precondicoes="ana favoritou o posto exato",
            passos="POST /rest/v1/rpc/meus_favoritos", entrada="-", esperado="1 posto, o de teste", severidade=MEDIA)

    # Perfis
    r = http("GET", "/rest/v1/perfis?select=id,nome,pontos", token=bruno["token"])
    ids = [x.get("id") for x in r.corpo] if isinstance(r.corpo, list) else []
    s.check(r.status == 200 and ids == [bruno["id"]], obtido=f"HTTP {r.status}; perfis visíveis: {len(ids)}", **Z, tela="Perfil",
            tipo="Segurança · IDOR", cenario="Usuário lê só o próprio perfil", precondicoes="Vários perfis no banco",
            passos="GET /rest/v1/perfis com token do bruno", entrada="-", esperado="Só o perfil do bruno", severidade=ALTA)
    r = http("PATCH", f"/rest/v1/perfis?id=eq.{ana['id']}", {"nome": "Invadido"}, token=bruno["token"],
             cabecalhos={"Prefer": "return=representation"})
    nome = um(db, "select nome from public.perfis where id=%s", ana["id"])
    s.check(nome != "Invadido", obtido=f"{resumo(r, 100)}; nome da ana: {nome}", **Z, tela="Alterar dados", tipo="Segurança · IDOR",
            cenario="Usuário não altera o perfil de outra pessoa", precondicoes="-", passos="PATCH perfis da ana com token do bruno",
            entrada="nome 'Invadido'", esperado="Nome da ana inalterado", severidade=CRITICA)
    for coluna, valor in (("pontos", 999999), ("confiabilidade", 1), ("banido", False), ("bloqueado_ate", None)):
        alvo = u["banido"] if coluna == "banido" else (u["bloqueado"] if coluna == "bloqueado_ate" else ana)
        antes = um(db, f"select {coluna}::text from public.perfis where id=%s", alvo["id"])
        r = http("PATCH", f"/rest/v1/perfis?id=eq.{alvo['id']}", {coluna: valor}, token=alvo["token"])
        depois = um(db, f"select {coluna}::text from public.perfis where id=%s", alvo["id"])
        s.check(r.status in (400, 401, 403) and antes == depois, obtido=f"{resumo(r, 140)}; antes {antes}, depois {depois}", **Z,
                tela="Alterar dados", tipo="Segurança · coluna protegida",
                cenario=f"Usuário não altera a coluna {coluna} do próprio perfil", precondicoes="Usuário logado",
                passos=f"PATCH perfis {{{coluna}}}", entrada=f"{coluna}={valor}", esperado="Recusado; valor inalterado",
                severidade=CRITICA)
    r = http("PATCH", f"/rest/v1/perfis?id=eq.{ana['id']}", {"nome": "Auditoria Ana Souza"}, token=ana["token"],
             cabecalhos={"Prefer": "return=representation"})
    s.check(r.status == 200 and isinstance(r.corpo, list) and len(r.corpo) == 1, obtido=resumo(r, 120), aba="Funcionais",
            modulo="Perfil", tela="Alterar dados", tipo="Funcional · positivo", cenario="Usuária altera o próprio nome",
            precondicoes="ana logada", passos="PATCH perfis {nome}", entrada="'Auditoria Ana Souza'", esperado="HTTP 200 com a linha",
            severidade=MEDIA)
    for desc, nome_n in (("1 caractere", "A"), ("61 caracteres", "N" * 61)):
        r = http("PATCH", f"/rest/v1/perfis?id=eq.{ana['id']}", {"nome": nome_n}, token=ana["token"])
        s.check(r.status == 400, obtido=resumo(r, 160), aba="Banco de Dados", modulo="Perfil", tela="Alterar dados",
                tipo="Banco · validação", cenario=f"Nome com {desc} é recusado", precondicoes="ana logada", passos="PATCH perfis {nome}",
                entrada=desc, esperado="HTTP 400 (2 a 60 caracteres)", severidade=BAIXA)

    # Notificações
    db.execute("insert into public.notificacoes (usuario_id, posto_id, produto_id, preco_anterior, preco_novo) values (%s, %s, 1, 6.10, 5.99)",
               (ana["id"], p["exata"]))
    nid = um(db, "select max(id) from public.notificacoes where usuario_id=%s", ana["id"])
    r = http("GET", "/rest/v1/notificacoes?select=*", token=bruno["token"])
    s.check(r.status == 200 and r.corpo == [], obtido=resumo(r, 120), **Z, tela="Avisos de preço", tipo="Segurança · IDOR",
            cenario="Usuário não vê os avisos de outra pessoa", precondicoes="ana tem 1 aviso", passos="GET notificacoes com token do bruno",
            entrada="-", esperado="Lista vazia", severidade=ALTA)
    r = http("PATCH", f"/rest/v1/notificacoes?id=eq.{nid}", {"preco_novo": 1.0}, token=ana["token"])
    pn = um(db, "select preco_novo::text from public.notificacoes where id=%s", nid)
    s.check(r.status in (400, 401, 403) and pn == "5.990", obtido=f"{resumo(r, 120)}; preco_novo={pn}", **Z, tela="Avisos de preço",
            tipo="Segurança · coluna protegida", cenario="Dona do aviso só consegue marcar como lido, não alterar o preço",
            precondicoes="ana logada", passos="PATCH notificacoes {preco_novo}", entrada="1,00", esperado="Recusado", severidade=MEDIA)
    r = http("PATCH", f"/rest/v1/notificacoes?id=eq.{nid}", {"lida": True}, token=ana["token"], cabecalhos={"Prefer": "return=representation"})
    lida = um(db, "select lida from public.notificacoes where id=%s", nid)
    s.check(r.status == 200 and lida is True, obtido=f"{resumo(r, 100)}; lida={lida}", aba="Funcionais", modulo="Avisos de preço",
            tela="Avisos de preço", tipo="Funcional · positivo", cenario="Marcar aviso como lido", precondicoes="ana com aviso não lido",
            passos="PATCH notificacoes {lida: true}", entrada="-", esperado="HTTP 200; lida = true", severidade=BAIXA)

    # Tabelas só do servidor
    for t, corpo in (("envios", {"posto_id": p["exata"], "usuario_id": ana["id"], "posicao": "SRID=4326;POINT(-59.5 -10.5)", "distancia_m": 0}),
                     ("envio_itens", {"envio_id": "00000000-0000-0000-0000-000000000000", "posto_id": p["exata"], "produto_id": 1, "preco": 5}),
                     ("pontos_movimentos", {"usuario_id": ana["id"], "tipo": "x", "pontos": 1000, "descricao": "x"}),
                     ("correcoes_posicao", {"posto_id": p["rua"], "usuario_id": ana["id"], "posicao": "SRID=4326;POINT(-59.6 -10.6)"}),
                     ("precos_atuais", {"posto_id": p["rua"], "produto_id": 1, "preco": 1, "fonte": "comunidade", "situacao": "confirmado", "atualizado_em": "2026-10-06T00:00:00Z"}),
                     ("notificacoes", {"usuario_id": ana["id"], "posto_id": p["exata"], "produto_id": 1, "preco_anterior": 1, "preco_novo": 2})):
        r = http("POST", f"/rest/v1/{t}", corpo, token=ana["token"])
        s.check(r.status in (401, 403), obtido=resumo(r, 160), **Z, tela=f"Tabela {t}", tipo="Segurança · escrita direta",
                cenario=f"Usuário logado não grava direto em {t} (só o servidor grava)", precondicoes="ana logada",
                passos=f"POST /rest/v1/{t} com token", entrada=json.dumps(corpo)[:200], esperado="HTTP 401/403",
                severidade=CRITICA if t in ("envio_itens", "pontos_movimentos", "precos_atuais") else ALTA)
    ctx["notificacao_ana"] = nid


# ------------------------------------------------------------------ enviar-precos
def _enviar(token, posto, lat, lon, itens, extra=None):
    corpo = {"posto_id": posto, "latitude": lat, "longitude": lon, "itens": itens, "app_versao": "auditoria"}
    corpo.update(extra or {})
    return http("POST", F_ENVIAR, corpo, token=token, timeout=90)


def enviar_precos(s, ctx) -> None:
    db, u, p = ctx["db"], ctx["usuarios"], ctx["postos"]
    E = dict(aba="Edge Functions", modulo="enviar-precos", tela="Enviar preços")
    lat0, lon0 = -10.5, -59.5
    perto = deslocar(lat0, lon0, 100)

    # Sem login, método, CORS
    r = http("POST", F_ENVIAR, {"posto_id": p["exata"]})
    s.check(r.status == 401, obtido=resumo(r, 160), **E, tipo="Segurança · autenticação", cenario="Envio sem login é recusado",
            precondicoes="Sem token", passos="POST sem Authorization", entrada="corpo mínimo", esperado="HTTP 401", severidade=CRITICA)
    r = http("GET", F_ENVIAR, token=u["ana"]["token"])
    s.check(r.status == 405, obtido=resumo(r, 160), **E, tipo="Funcional · método", cenario="GET é recusado", precondicoes="-",
            passos="GET", entrada="-", esperado="HTTP 405", severidade=BAIXA)
    r = http("OPTIONS", F_ENVIAR)
    cors = r.cabecalhos.get("Access-Control-Allow-Origin") or r.cabecalhos.get("access-control-allow-origin")
    s.check(r.status == 200 and cors == "*", obtido=f"HTTP {r.status}; Allow-Origin: {cors}", **E, tipo="Integração · CORS",
            cenario="Pré-requisição CORS responde com os cabeçalhos", precondicoes="-", passos="OPTIONS", entrada="-",
            esperado="HTTP 200 e Access-Control-Allow-Origin", severidade=BAIXA)

    # Corpo inválido
    invalidos = [
        ("JSON malformado", None, b"{nao e json", "Corpo da requisição inválido"),
        ("sem posto_id", {"latitude": perto[0], "longitude": perto[1], "itens": [{"produto_id": 1, "preco": 5.99}]}, None, "Posto não informado"),
        ("posto_id como texto", {"posto_id": str(p["exata"]), "latitude": perto[0], "longitude": perto[1], "itens": [{"produto_id": 1, "preco": 5.99}]}, None, "Posto não informado"),
        ("latitude 91", {"posto_id": p["exata"], "latitude": 91, "longitude": perto[1], "itens": [{"produto_id": 1, "preco": 5.99}]}, None, "Localização"),
        ("sem itens", {"posto_id": p["exata"], "latitude": perto[0], "longitude": perto[1], "itens": []}, None, "pelo menos um"),
        ("7 itens", {"posto_id": p["exata"], "latitude": perto[0], "longitude": perto[1], "itens": [{"produto_id": i, "preco": 5} for i in range(1, 8)]}, None, "mais preços"),
        ("combustível inexistente", {"posto_id": p["exata"], "latitude": perto[0], "longitude": perto[1], "itens": [{"produto_id": 99, "preco": 5}]}, None, "desconhecido"),
        ("combustível repetido", {"posto_id": p["exata"], "latitude": perto[0], "longitude": perto[1], "itens": [{"produto_id": 1, "preco": 5}, {"produto_id": 1, "preco": 5.1}]}, None, "mais de uma vez"),
        ("preço abaixo do mínimo (R$ 1,99)", {"posto_id": p["exata"], "latitude": perto[0], "longitude": perto[1], "itens": [{"produto_id": 1, "preco": 1.99}]}, None, "entre R$"),
        ("preço acima do máximo (R$ 15,01)", {"posto_id": p["exata"], "latitude": perto[0], "longitude": perto[1], "itens": [{"produto_id": 1, "preco": 15.01}]}, None, "entre R$"),
        ("preço como texto", {"posto_id": p["exata"], "latitude": perto[0], "longitude": perto[1], "itens": [{"produto_id": 1, "preco": "5.99"}]}, None, "inválido"),
        ("preço negativo", {"posto_id": p["exata"], "latitude": perto[0], "longitude": perto[1], "itens": [{"produto_id": 1, "preco": -5}]}, None, "entre R$"),
    ]
    for desc, corpo, bruto, trecho in invalidos:
        r = http("POST", F_ENVIAR, corpo, token=u["ana"]["token"], bruto=bruto)
        s.check(r.status == 422 and trecho.lower() in r.texto.lower(), obtido=resumo(r, 200), **E, tipo="Funcional · validação",
                cenario=f"Envio com {desc} é recusado com mensagem clara", precondicoes="ana logada", passos=f"POST {F_ENVIAR}",
                entrada=(bruto.decode() if bruto else json.dumps(corpo))[:250], esperado=f"HTTP 422 com '{trecho}'", severidade=MEDIA)
    n = um(db, "select count(*) from public.envios where posto_id = any(%s)", list(p.values()))
    s.check(n == 0, obtido=f"envios gravados nos postos de teste: {n}", aba="Banco de Dados", modulo="enviar-precos", tela="Tabela envios",
            tipo="Banco · integridade", cenario="Envios recusados não deixam linha no banco", precondicoes="12 envios inválidos acima",
            passos="Contar envios dos postos de teste", entrada="-", esperado="0", severidade=ALTA)

    # Fluxo positivo e consenso
    r = _enviar(u["ana"]["token"], p["exata"], *perto, [{"produto_id": 1, "preco": 5.99, "preco_lido": 5.99, "confianca": 0.93},
                                                       {"produto_id": 3, "preco": 4.19}],
                {"ocr_texto": "GASOLINA 5,99 ETANOL 4,19 " + "x" * 3000, "ocr_duracao_ms": 850})
    itens = r.corpo.get("itens") if isinstance(r.corpo, dict) else None
    s.check(r.status == 200 and itens and all(i["status"] == "pendente" for i in itens), obtido=resumo(r, 300), **E,
            tipo="Funcional · positivo", cenario="Primeiro envio válido a 100 m do posto fica pendente", precondicoes="ana logada, a 100 m",
            passos="POST com 2 preços", entrada="gasolina 5,99; etanol 4,19", esperado="HTTP 200, itens pendentes", severidade=CRITICA)
    linha = db.execute("select distancia_m, char_length(ocr_texto), app_versao, ocr_duracao_ms from public.envios where usuario_id=%s",
                       (u["ana"]["id"],)).fetchone()
    s.check(linha and 90 <= linha[0] <= 110 and linha[1] == 2000 and linha[2] == "auditoria",
            obtido=f"distancia_m={linha and linha[0]}, ocr_texto={linha and linha[1]} caracteres, versão={linha and linha[2]}",
            aba="Banco de Dados", modulo="enviar-precos", tela="Tabela envios", tipo="Banco · integridade",
            cenario="Envio gravado com distância real, texto lido cortado em 2.000 caracteres e versão do app",
            precondicoes="Envio da ana aceito", passos="Ler a linha em envios", entrada="texto de 3.026 caracteres",
            esperado="distancia_m ≈ 100; 2000 caracteres; versão 'auditoria'", severidade=MEDIA)
    pa = db.execute("select preco::text, fonte::text, situacao::text from public.precos_atuais where posto_id=%s and produto_id=1",
                    (p["exata"],)).fetchone()
    s.check(pa is not None and pa[2] == "nao_confirmado" and pa[1] == "comunidade", obtido=f"precos_atuais gasolina: {pa}",
            aba="Banco de Dados", modulo="Consenso", tela="Tabela precos_atuais", tipo="Regra de negócio",
            cenario="Envio isolado sem divergência aparece como 'aguardando confirmação', nunca como confirmado",
            precondicoes="Preço oficial 6,00; 1 envio de 5,99 nas últimas 24 h", passos="Ler precos_atuais",
            entrada="-", esperado="fonte comunidade, situação nao_confirmado (prioridade 2 da ordem documentada)", severidade=CRITICA)
    regra = "O envio é uma proposta: ele nunca altera o preço exibido diretamente."
    from comum import RAIZ
    catalogo = (RAIZ / "scripts" / "docs" / "gerar_regras.py").read_text(encoding="utf-8")
    contradiz = regra in catalogo and pa is not None and pa[1] == "comunidade"
    s.check(not contradiz, obtido=f"Comportamento: o preço exibido passou a {pa} logo após um único envio. "
                                  f"Regra no catálogo: '{regra}' ({'presente' if regra in catalogo else 'ausente'})",
            aba="Funcionais", modulo="Documentação das regras", tela="Regras de negócio (RN do envio por foto)",
            tipo="Consistência · documentação", cenario="Texto da regra bate com o comportamento do preço exibido",
            precondicoes="Página de regras publicada", passos="Comparar a regra do catálogo com o resultado do teste anterior",
            entrada="-", esperado="Regra e comportamento iguais", severidade=BAIXA,
            obs="A ordem de prioridade da mesma página (item 2, 'Envio recente sem divergência') descreve o comportamento real. "
                "A frase da regra precisa dizer que o envio aparece como 'aguardando confirmação' e nunca como confirmado.")

    r = _enviar(u["bruno"]["token"], p["exata"], *deslocar(lat0, lon0, -150), [{"produto_id": 1, "preco": 6.01}])
    st = (r.corpo.get("itens") or [{}])[0].get("status") if isinstance(r.corpo, dict) else None
    s.check(r.status == 200 and st == "confirmado", obtido=resumo(r, 300), **E, tipo="Regra de negócio · consenso",
            cenario="Segundo usuário com diferença de R$ 0,02 confirma o preço", precondicoes="Envio pendente da ana (5,99)",
            passos="bruno envia 6,01 a 150 m", entrada="gasolina 6,01", esperado="Item confirmado", severidade=CRITICA)
    pa = db.execute("select preco::text, fonte::text, situacao::text, confirmacoes from public.precos_atuais where posto_id=%s and produto_id=1",
                    (p["exata"],)).fetchone()
    s.check(pa and pa[1] == "comunidade" and pa[2] == "confirmado", obtido=f"precos_atuais gasolina: {pa}", aba="Banco de Dados",
            modulo="Consenso", tela="Tabela precos_atuais", tipo="Regra de negócio", cenario="Preço exibido passa a ser o da comunidade, confirmado",
            precondicoes="Consenso formado", passos="Ler precos_atuais", entrada="-", esperado="fonte comunidade, situação confirmado",
            severidade=CRITICA)
    pts = {n: um(db, "select pontos from public.perfis where id=%s", u[n]["id"]) for n in ("ana", "bruno")}
    s.check(pts["ana"] >= 10 and pts["bruno"] >= 10, obtido=f"pontos: {pts}", aba="Banco de Dados", modulo="Pontos",
            tela="Tabela perfis", tipo="Regra de negócio", cenario="Os dois envios do consenso ganham pelo menos 10 pontos",
            precondicoes="Consenso formado", passos="Ler perfis.pontos", entrada="-", esperado="≥ 10 cada (10 + bônus de 5 ao primeiro)",
            severidade=ALTA)
    st_ana = um(db, "select status::text from public.envio_itens where usuario_id=%s and produto_id=1", u["ana"]["id"])
    s.check(st_ana == "confirmado", obtido=f"status do item da ana: {st_ana}", aba="Banco de Dados", modulo="Consenso",
            tela="Tabela envio_itens", tipo="Regra de negócio", cenario="Item pendente da primeira pessoa vira confirmado",
            precondicoes="Consenso formado", passos="Ler envio_itens", entrada="-", esperado="confirmado", severidade=ALTA)
    hist = um(db, "select count(*) from public.precos_comunidade where posto_id=%s and produto_id=1 and confirmado", p["exata"])
    s.check(hist == 1, obtido=f"linhas confirmadas em precos_comunidade: {hist}", aba="Banco de Dados", modulo="Histórico",
            tela="Tabela precos_comunidade", tipo="Regra de negócio", cenario="Consenso entra no histórico diário da comunidade",
            precondicoes="Consenso formado", passos="Ler precos_comunidade", entrada="-", esperado="1 linha confirmada", severidade=MEDIA)
    av = um(db, "select count(*) from public.notificacoes where usuario_id=%s and posto_id=%s and produto_id=1", u["ana"]["id"], p["exata"])
    novo_preco = float(pa[0]) if pa else 0
    deve_avisar = abs(novo_preco - 6.0) >= 0.05
    s.check(av == (2 if deve_avisar else 1), obtido=f"preço do consenso {novo_preco:.3f}; avisos da ana para o posto: {av} (1 criado antes pela auditoria)",
            aba="Banco de Dados", modulo="Avisos de preço", tela="Tabela notificacoes", tipo="Regra de negócio",
            cenario="Aviso a quem favoritou só sai quando o preço confiável muda R$ 0,05 ou mais",
            precondicoes="ana favoritou o posto; último preço confiável 6,00", passos="Contar avisos da ana depois do consenso",
            entrada=f"6,000 → {novo_preco:.3f}", esperado=f"{'novo aviso' if deve_avisar else 'nenhum aviso novo'} (variação {abs(novo_preco - 6):.3f})",
            severidade=MEDIA)

    r = _enviar(u["carla"]["token"], p["exata"], *perto, [{"produto_id": 1, "preco": 8.50}])
    it = (r.corpo.get("itens") or [{}])[0] if isinstance(r.corpo, dict) else {}
    s.check(r.status == 200 and it.get("em_revisao") is True, obtido=resumo(r, 300), **E, tipo="Regra de negócio · revisão",
            cenario="Envio 40% acima da referência entra em revisão", precondicoes="Preço confirmado ~6,00", passos="carla envia 8,50",
            entrada="gasolina 8,50", esperado="em_revisao = true, com motivo", severidade=ALTA)
    r = _enviar(u["ana"]["token"], p["exata"], *perto, [{"produto_id": 1, "preco": 5.98}])
    s.check(r.status == 429, obtido=resumo(r, 200), **E, tipo="Regra de negócio · limite", cenario="Mesmo usuário, posto e combustível em menos de 6 h é recusado",
            precondicoes="ana enviou gasolina há instantes", passos="ana envia gasolina de novo", entrada="5,98",
            esperado="HTTP 429", severidade=MEDIA)
    r = _enviar(u["ana"]["token"], p["exata"], *perto, [{"produto_id": 1, "preco": 5.98}, {"produto_id": 2, "preco": 6.29}])
    ign = r.corpo.get("ignorados") if isinstance(r.corpo, dict) else None
    s.check(r.status == 200 and ign == [1], obtido=resumo(r, 250), **E, tipo="Regra de negócio · limite",
            cenario="Envio misto: o combustível repetido é ignorado e o novo é aceito", precondicoes="ana enviou gasolina há instantes",
            passos="ana envia gasolina e aditivada", entrada="5,98 e 6,29", esperado="HTTP 200, ignorados = [1]", severidade=MEDIA)

    # Distância e precisão
    longe = deslocar(lat0, lon0, 500)
    r = _enviar(u["davi"]["token"], p["exata"], *longe, [{"produto_id": 1, "preco": 6.0}])
    s.check(r.status == 422 and "300 m" in r.texto, obtido=resumo(r, 250), **E, tipo="Regra de negócio · raio",
            cenario="Posto com posição exata: envio a 500 m é recusado (raio 300 m)", precondicoes="davi a 500 m",
            passos="POST a 500 m", entrada="gasolina 6,00", esperado="HTTP 422 citando 300 m", severidade=CRITICA)
    limite = deslocar(lat0, lon0, 295)
    r = _enviar(u["davi"]["token"], p["exata"], *limite, [{"produto_id": 4, "preco": 6.0}])
    s.check(r.status == 200, obtido=resumo(r, 200), **E, tipo="Regra de negócio · limite de raio",
            cenario="Envio a 295 m do posto exato é aceito (borda do raio)", precondicoes="davi a 295 m", passos="POST a 295 m",
            entrada="diesel S500 6,00", esperado="HTTP 200", severidade=MEDIA)
    rlat, rlon = -10.6, -59.6
    r = _enviar(u["davi"]["token"], p["rua"], *deslocar(rlat, rlon, 800), [{"produto_id": 1, "preco": 6.0}])
    s.check(r.status == 200, obtido=resumo(r, 200), **E, tipo="Regra de negócio · posição aproximada",
            cenario="Posto com posição pela rua: envio a 800 m é aceito (raio 1 km)", precondicoes="davi a 800 m",
            passos="POST a 800 m do posto 'rua'", entrada="gasolina 6,00", esperado="HTTP 200", severidade=CRITICA)
    r = _enviar(u["davi"]["token"], p["rua"], *deslocar(rlat, rlon, 1500), [{"produto_id": 3, "preco": 4.0}])
    s.check(r.status == 422 and "1 km" in r.texto and "aproximada" in r.texto, obtido=resumo(r, 250), **E,
            tipo="Regra de negócio · posição aproximada", cenario="Posto com posição pela rua: envio a 1,5 km é recusado com mensagem de 1 km",
            precondicoes="davi a 1,5 km", passos="POST a 1,5 km", entrada="etanol 4,00", esperado="HTTP 422 citando 1 km e posição aproximada",
            severidade=ALTA)
    for chave, desc in (("sem_local", "sem localização"), ("cidade", "localizado só pelo CEP da cidade")):
        r = _enviar(u["davi"]["token"], p[chave], -10.8, -59.8, [{"produto_id": 1, "preco": 6.0}])
        s.check(r.status == 422 and "Estou neste posto" in r.texto, obtido=resumo(r, 250), **E, tipo="Regra de negócio · posição desconhecida",
                cenario=f"Posto {desc} não aceita envio e orienta a usar 'Estou neste posto'", precondicoes="davi logado",
                passos="POST", entrada="gasolina 6,00", esperado="HTTP 422 com a orientação", severidade=ALTA)
    r = _enviar(u["davi"]["token"], p["inativo"], -10.7, -59.7, [{"produto_id": 1, "preco": 6.0}])
    s.check(r.status == 404, obtido=resumo(r, 200), **E, tipo="Funcional · negativo", cenario="Posto inativo não aceita envio",
            precondicoes="Posto fora do cadastro da ANP (ativo = false)", passos="POST no lugar do posto", entrada="gasolina 6,00",
            esperado="HTTP 404 'Posto não encontrado'", severidade=MEDIA)
    r = _enviar(u["davi"]["token"], 999999999, -10.5, -59.5, [{"produto_id": 1, "preco": 6.0}])
    s.check(r.status == 404, obtido=resumo(r, 200), **E, tipo="Funcional · negativo", cenario="Posto inexistente", precondicoes="-",
            passos="POST com posto_id 999999999", entrada="-", esperado="HTTP 404", severidade=BAIXA)

    # Contas sem permissão
    for nome, esp in (("banido", "não pode enviar"), ("bloqueado", "pausados")):
        r = _enviar(u[nome]["token"], p["exata"], *perto, [{"produto_id": 5, "preco": 6.0}])
        s.check(r.status == 403 and esp in r.texto, obtido=resumo(r, 200), **E, tipo="Segurança · conta suspensa",
                cenario=f"Conta {nome} não envia preços", precondicoes=f"perfil {nome}", passos="POST válido", entrada="diesel S10 6,00",
                esperado=f"HTTP 403 com '{esp}'", severidade=CRITICA)
    db.execute("update auth.users set email_confirmed_at = null where id = %s", (u["davi"]["id"],))
    r = _enviar(u["davi"]["token"], p["exata"], *perto, [{"produto_id": 5, "preco": 6.0}])
    db.execute("update auth.users set email_confirmed_at = now() where id = %s", (u["davi"]["id"],))
    s.check(r.status == 403 and "Confirme" in r.texto, obtido=resumo(r, 200), **E, tipo="Segurança · e-mail não confirmado",
            cenario="Sessão de conta cujo e-mail deixou de estar confirmado não envia preços", precondicoes="email_confirmed_at nulo",
            passos="POST com token válido", entrada="-", esperado="HTTP 403 'Confirme seu e-mail'", severidade=ALTA)

    # Limite diário de 20 envios
    db.execute("""insert into public.envios (usuario_id, posto_id, posicao, distancia_m, criado_em)
                  select %s, %s, 'SRID=4326;POINT(-59.5 -10.5)'::extensions.geography, 0, now() - interval '1 hour'
                  from generate_series(1, 20)""", (u["carla"]["id"], p["exata"]))
    r = _enviar(u["carla"]["token"], p["exata"], *perto, [{"produto_id": 6, "preco": 4.5}])
    s.check(r.status == 429 and "20" in r.texto, obtido=resumo(r, 200), **E, tipo="Regra de negócio · limite diário",
            cenario="21º envio em 24 horas é recusado", precondicoes="carla com 20 envios na última hora (inseridos no banco)",
            passos="POST válido", entrada="GNV 4,50", esperado="HTTP 429 citando 20 envios", severidade=ALTA)

    # Concorrência: 6 envios simultâneos do mesmo item
    def tentar(_):
        return _enviar(u["bruno"]["token"], p["exata"], *perto, [{"produto_id": 5, "preco": 6.10}])
    with cf.ThreadPoolExecutor(max_workers=6) as ex:
        rs = list(ex.map(tentar, range(6)))
    aceitos = sum(x.status == 200 for x in rs)
    itens_db = um(db, "select count(*) from public.envio_itens where usuario_id=%s and produto_id=5", u["bruno"]["id"])
    s.check(itens_db == 1, obtido=f"respostas: {[x.status for x in rs]}; itens gravados: {itens_db}", aba="Performance",
            modulo="enviar-precos", tela="Enviar preços", tipo="Concorrência", cenario="6 envios simultâneos do mesmo item geram um só registro",
            precondicoes="bruno logado, a 100 m", passos="Disparar 6 POST iguais ao mesmo tempo; contar itens no banco",
            entrada="diesel S10 6,10 ×6", esperado="1 aceito; 5 recusados com 429", severidade=ALTA,
            obs="Verifica a regra de 6 h sob concorrência (a checagem e a gravação não são atômicas).")
    ctx["concorrencia_enviar"] = (aceitos, itens_db)

    # Efeito da duplicidade: quando outra pessoa confirma, quantos pontos o bruno ganha por uma única ação?
    pts_antes = um(db, "select pontos from public.perfis where id=%s", u["bruno"]["id"])
    conf_antes = um(db, "select confiabilidade from public.perfis where id=%s", u["bruno"]["id"])
    r = _enviar(u["ana"]["token"], p["exata"], *perto, [{"produto_id": 5, "preco": 6.10}])
    pts_depois = um(db, "select pontos from public.perfis where id=%s", u["bruno"]["id"])
    conf_depois = um(db, "select confiabilidade from public.perfis where id=%s", u["bruno"]["id"])
    ganho = (pts_depois or 0) - (pts_antes or 0)
    s.check(ganho <= 15, obtido=f"confirmação da ana: HTTP {r.status}; pontos do bruno {pts_antes} → {pts_depois} (+{ganho}); "
                                f"confiabilidade {conf_antes} → {conf_depois}",
            aba="Segurança", modulo="Pontos", tela="Enviar preços", tipo="Segurança · abuso de regra",
            cenario="Envios duplicados por concorrência não multiplicam pontos nem confiabilidade",
            precondicoes=f"bruno com {itens_db} itens iguais gravados ao mesmo tempo (teste anterior)",
            passos="ana envia o mesmo preço e forma o consenso; comparar pontos do bruno antes e depois",
            entrada="diesel S10 6,10", esperado="Ganho de no máximo 15 pontos (10 + bônus de 5) por uma ação",
            severidade=ALTA, obs="Cada item confirmado chama registrar_pontos e ajustar_confiabilidade.")

    # Confiança da leitura acima de 1 é limitada a 1
    r = _enviar(u["davi"]["token"], p["rua"], *deslocar(-10.6, -59.6, 100), [{"produto_id": 4, "preco": 6.2, "preco_lido": 6.25, "confianca": 7}])
    linha = db.execute("select confianca_ocr, preco_lido::text, editado from public.envio_itens where usuario_id=%s and posto_id=%s and produto_id=4",
                       (u["davi"]["id"], p["rua"])).fetchone()
    s.check(r.status == 200 and linha is not None and float(linha[0]) == 1.0 and linha[2] is True,
            obtido=f"{resumo(r, 120)}; linha gravada: {linha}", aba="Banco de Dados", modulo="enviar-precos", tela="Tabela envio_itens",
            tipo="Banco · normalização", cenario="Confiança da leitura acima de 1 é limitada a 1 e valor corrigido marca 'editado'",
            precondicoes="davi logado, a 100 m do posto 'rua'",
            passos="POST com confianca 7 e preço diferente do lido", entrada="preço 6,20; lido 6,25; confiança 7",
            esperado="confianca_ocr = 1; editado = true", severidade=BAIXA)


# ------------------------------------------------------------------ corrigir-posicao
def _posicao(token, posto, lat, lon, gps=10.0, extra=None):
    corpo = {"posto_id": posto, "latitude": lat, "longitude": lon, "precisao_gps_m": gps}
    corpo.update(extra or {})
    return http("POST", F_POSICAO, corpo, token=token, timeout=60)


def corrigir_posicao(s, ctx) -> None:
    db, u, p = ctx["db"], ctx["usuarios"], ctx["postos"]
    E = dict(aba="Edge Functions", modulo="corrigir-posicao", tela="Estou neste posto")
    rlat, rlon = -10.6, -59.6

    r = http("POST", F_POSICAO, {"posto_id": p["rua"]})
    s.check(r.status == 401, obtido=resumo(r, 160), **E, tipo="Segurança · autenticação", cenario="Sem login é recusado", precondicoes="-",
            passos="POST sem token", entrada="-", esperado="HTTP 401", severidade=CRITICA)
    r = http("GET", F_POSICAO, token=u["ana"]["token"])
    s.check(r.status == 405, obtido=resumo(r, 120), **E, tipo="Funcional · método", cenario="GET é recusado", precondicoes="-",
            passos="GET", entrada="-", esperado="HTTP 405", severidade=BAIXA)
    r = http("OPTIONS", F_POSICAO)
    s.check(r.status == 200, obtido=f"HTTP {r.status}", **E, tipo="Integração · CORS", cenario="Pré-requisição CORS", precondicoes="-",
            passos="OPTIONS", entrada="-", esperado="HTTP 200", severidade=BAIXA)
    invalidos = [
        ("JSON malformado", None, b"[1,2", "inválido"),
        ("sem posto", {"latitude": rlat, "longitude": rlon, "precisao_gps_m": 10}, None, "Posto não informado"),
        ("fora do Brasil (Lisboa)", {"posto_id": p["rua"], "latitude": 38.7, "longitude": -9.1, "precisao_gps_m": 10}, None, "fora do Brasil"),
        ("latitude 91", {"posto_id": p["rua"], "latitude": 91, "longitude": rlon, "precisao_gps_m": 10}, None, "inválida"),
        ("sem precisão do GPS", {"posto_id": p["rua"], "latitude": rlat, "longitude": rlon}, None, "precisão do GPS"),
        ("precisão do GPS 0", {"posto_id": p["rua"], "latitude": rlat, "longitude": rlon, "precisao_gps_m": 0}, None, "precisão do GPS"),
        ("GPS impreciso (150 m)", {"posto_id": p["rua"], "latitude": rlat, "longitude": rlon, "precisao_gps_m": 150}, None, "impreciso"),
    ]
    for desc, corpo, bruto, trecho in invalidos:
        r = http("POST", F_POSICAO, corpo, token=u["ana"]["token"], bruto=bruto)
        s.check(r.status == 422 and trecho.lower() in r.texto.lower(), obtido=resumo(r, 200), **E, tipo="Funcional · validação",
                cenario=f"Posição com {desc} é recusada", precondicoes="ana logada", passos=f"POST {F_POSICAO}",
                entrada=(bruto.decode() if bruto else json.dumps(corpo)), esperado=f"HTTP 422 com '{trecho}'", severidade=MEDIA)
    r = _posicao(u["ana"]["token"], p["rua"], rlat, rlon, gps=100)
    s.check(r.status == 200, obtido=resumo(r, 200), **E, tipo="Funcional · limite", cenario="GPS com precisão de exatamente 100 m é aceito",
            precondicoes="ana logada", passos="POST com precisao_gps_m 100", entrada="100 m", esperado="HTTP 200", severidade=BAIXA)

    # Consenso de posição
    a = deslocar(rlat, rlon, 400, 300)
    r = _posicao(u["ana"]["token"], p["rua"], *a)
    st = r.corpo.get("status") if isinstance(r.corpo, dict) else None
    s.check(r.status == 200 and st == "aguardando", obtido=resumo(r, 250), **E, tipo="Regra de negócio · consenso de posição",
            cenario="Primeira posição informada fica aguardando outra pessoa", precondicoes="Posto com posição pela rua",
            passos="ana informa um ponto a 500 m do ponto aproximado", entrada="GPS 10 m", esperado="status aguardando", severidade=ALTA)
    n = um(db, "select count(*) from public.correcoes_posicao where usuario_id=%s and posto_id=%s and status='pendente'",
           u["ana"]["id"], p["rua"])
    s.check(n == 1, obtido=f"posições pendentes da ana no posto: {n}", aba="Banco de Dados", modulo="corrigir-posicao",
            tela="Tabela correcoes_posicao", tipo="Banco · unicidade", cenario="Informar duas vezes atualiza a mesma posição pendente",
            precondicoes="ana informou 2 vezes (100 m de GPS e depois o ponto certo)", passos="Contar pendentes da ana",
            entrada="-", esperado="1", severidade=MEDIA)
    r = _posicao(u["ana"]["token"], p["rua"], *deslocar(*a, 20))
    st = r.corpo.get("status") if isinstance(r.corpo, dict) else None
    s.check(r.status == 200 and st == "aguardando", obtido=resumo(r, 200), **E, tipo="Regra de negócio · consenso de posição",
            cenario="A mesma pessoa informando de novo não confirma sozinha", precondicoes="ana já informou",
            passos="ana informa de novo, 20 m ao lado", entrada="-", esperado="Continua aguardando", severidade=ALTA)
    r = _posicao(u["carla"]["token"], p["rua"], *deslocar(*a, 600))
    st = r.corpo.get("status") if isinstance(r.corpo, dict) else None
    s.check(r.status == 200 and st == "aguardando", obtido=resumo(r, 200), **E, tipo="Regra de negócio · consenso de posição",
            cenario="Segunda pessoa a 600 m da primeira não confirma (tolerância 150 m)", precondicoes="ana informou",
            passos="carla informa a 600 m", entrada="-", esperado="Continua aguardando", severidade=ALTA)
    b = deslocar(*a, 100)
    r = _posicao(u["bruno"]["token"], p["rua"], *b)
    st = r.corpo.get("status") if isinstance(r.corpo, dict) else None
    s.check(r.status == 200 and st == "confirmada", obtido=resumo(r, 250), **E, tipo="Regra de negócio · consenso de posição",
            cenario="Segunda pessoa a 100 m da primeira confirma a posição", precondicoes="ana informou",
            passos="bruno informa a 100 m", entrada="-", esperado="status confirmada", severidade=CRITICA)
    linha = db.execute("""select precisao_localizacao, localizacao_fonte, localizacao_validada,
                                 st_distance(localizacao, st_makepoint(%s, %s)::extensions.geography)
                          from public.postos where id=%s""", (a[1], a[0], p["rua"])).fetchone()
    s.check(linha and linha[0] == "exata" and linha[1] == "usuario" and linha[2] and linha[3] < 100,
            obtido=f"precisão={linha[0]}, fonte={linha[1]}, validada={linha[2]}, distância ao ponto da ana={linha[3]:.0f} m",
            aba="Banco de Dados", modulo="corrigir-posicao", tela="Tabela postos", tipo="Regra de negócio",
            cenario="Posto passa a ter posição exata no meio dos dois pontos", precondicoes="Consenso formado",
            passos="Ler o posto", entrada="-", esperado="exata, usuario, validada, ~50 m do ponto da ana", severidade=CRITICA)
    mov = {n: um(db, "select count(*) from public.pontos_movimentos where usuario_id=%s and tipo='posicao'", u[n]["id"])
           for n in ("ana", "bruno", "carla")}
    s.check(mov == {"ana": 1, "bruno": 1, "carla": 0}, obtido=f"movimentos de pontos por posição: {mov}", aba="Banco de Dados",
            modulo="Pontos", tela="Tabela pontos_movimentos", tipo="Regra de negócio",
            cenario="Só quem formou o consenso ganha os pontos da posição", precondicoes="Consenso formado",
            passos="Contar movimentos tipo 'posicao'", entrada="-", esperado="ana 1, bruno 1, carla 0", severidade=ALTA)
    stc = um(db, "select status from public.correcoes_posicao where usuario_id=%s and posto_id=%s", u["carla"]["id"], p["rua"])
    s.check(stc == "contestada", obtido=f"status da posição da carla: {stc}", aba="Banco de Dados", modulo="corrigir-posicao",
            tela="Tabela correcoes_posicao", tipo="Regra de negócio", cenario="Posição discordante é encerrada como contestada, sem punição",
            precondicoes="Consenso formado", passos="Ler a posição da carla", entrada="-", esperado="contestada", severidade=MEDIA)
    r = _posicao(u["davi"]["token"], p["rua"], *b)
    s.check(r.status == 409, obtido=resumo(r, 200), **E, tipo="Regra de negócio", cenario="Posto com posição já confirmada recusa nova posição",
            precondicoes="Posição confirmada", passos="davi informa", entrada="-", esperado="HTTP 409", severidade=MEDIA)
    r = _enviar(u["davi"]["token"], p["rua"], *deslocar(*b, 200), [{"produto_id": 6, "preco": 4.5}])
    s.check(r.status == 200, obtido=resumo(r, 200), aba="Integração", modulo="Posição → envio de preço", tela="Enviar preços",
            tipo="Integração · ponta a ponta", cenario="Depois da posição confirmada, o envio passa a usar o raio de 300 m em volta do ponto novo",
            precondicoes="Posição confirmada", passos="davi envia a 200 m do ponto novo", entrada="GNV 4,50", esperado="HTTP 200",
            severidade=ALTA)
    r = http("POST", "/rest/v1/rpc/postos_na_area", {"p_lat_min": -10.7, "p_lon_min": -59.7, "p_lat_max": -10.4, "p_lon_max": -59.4, "p_limite": 50})
    ids = [x["id"] for x in r.corpo] if isinstance(r.corpo, list) else []
    s.check(p["rua"] in ids and p["exata"] in ids and p["sem_local"] not in ids and p["inativo"] not in ids,
            obtido=f"HTTP {r.status}; ids no mapa: {ids}", aba="Integração", modulo="Mapa", tela="Mapa", tipo="Integração · banco → app",
            cenario="Mapa mostra os postos com posição conhecida e esconde os sem local e os inativos", precondicoes="Postos de teste",
            passos="POST rpc/postos_na_area na região dos postos de teste", entrada="caixa em volta de Rondônia/teste",
            esperado="exata e rua presentes; sem_local e inativo ausentes", severidade=ALTA)
    r = http("POST", "/rest/v1/rpc/postos_na_area", {"p_lat_min": -10.9, "p_lon_min": -59.9, "p_lat_max": -10.7, "p_lon_max": -59.7, "p_limite": 50})
    ids = [x["id"] for x in r.corpo] if isinstance(r.corpo, list) else []
    s.check(p["cidade"] not in ids, obtido=f"ids: {ids}", aba="Integração", modulo="Mapa", tela="Mapa", tipo="Regra de negócio",
            cenario="Posto localizado só pelo CEP da cidade não aparece no mapa", precondicoes="Posto 'cidade'", passos="postos_na_area",
            entrada="-", esperado="Ausente", severidade=MEDIA)
    r = http("POST", "/rest/v1/rpc/buscar_postos", {"p_texto": "auditoria sem local", "p_limite": 10})
    ids = [x["id"] for x in r.corpo] if isinstance(r.corpo, list) else []
    s.check(p["sem_local"] in ids, obtido=f"HTTP {r.status}; ids: {ids}", aba="Integração", modulo="Busca", tela="Busca",
            tipo="Regra de negócio", cenario="Posto sem local aparece na busca por nome (só sai do mapa)", precondicoes="Posto sem local",
            passos="buscar_postos 'auditoria sem local'", entrada="-", esperado="Presente", severidade=MEDIA)

    # Posto sem referência e longe demais
    r = _posicao(u["carla"]["token"], p["sem_local"], -9.0, -63.9)
    s.check(r.status == 200, obtido=resumo(r, 200), **E, tipo="Regra de negócio", cenario="Posto sem nenhuma posição aceita qualquer ponto do Brasil",
            precondicoes="Posto sem localização", passos="carla informa", entrada="Porto Velho", esperado="HTTP 200 aguardando", severidade=MEDIA)
    r = _posicao(u["carla"]["token"], p["cidade"], -12.0, -59.8)
    s.check(r.status == 422 and "100 km" in r.texto, obtido=resumo(r, 200), **E, tipo="Regra de negócio",
            cenario="Posição a mais de 100 km da posição aproximada é recusada", precondicoes="Posto 'cidade' em -10,8; -59,8",
            passos="carla informa a ~133 km", entrada="-", esperado="HTTP 422 citando 100 km", severidade=MEDIA)
    for desc, pid in (("inexistente", 999999999), ("inativo", p["inativo"])):
        r = _posicao(u["carla"]["token"], pid, -10.7, -59.7)
        s.check(r.status == 404, obtido=resumo(r, 160), **E, tipo="Funcional · negativo", cenario=f"Posto {desc}", precondicoes="-",
                passos="POST", entrada=str(pid), esperado="HTTP 404", severidade=BAIXA)
    for nome in ("banido", "bloqueado"):
        r = _posicao(u[nome]["token"], p["sem_local"], -9.0, -63.9)
        s.check(r.status == 403, obtido=resumo(r, 160), **E, tipo="Segurança · conta suspensa", cenario=f"Conta {nome} não informa posição",
                precondicoes=f"perfil {nome}", passos="POST válido", entrada="-", esperado="HTTP 403", severidade=ALTA)
    db.execute("""insert into public.correcoes_posicao (posto_id, usuario_id, posicao, status, criado_em)
                  select %s, %s, 'SRID=4326;POINT(-59.8 -10.8)'::extensions.geography, 'contestada', now() - interval '1 hour'
                  from generate_series(1, 10)""", (p["cidade"], u["davi"]["id"]))
    r = _posicao(u["davi"]["token"], p["sem_local"], -9.0, -63.9)
    s.check(r.status == 429, obtido=resumo(r, 200), **E, tipo="Regra de negócio · limite diário", cenario="11ª posição em 24 h é recusada",
            precondicoes="davi com 10 posições nas últimas 24 h (inseridas no banco)", passos="POST válido", entrada="-",
            esperado="HTTP 429", severidade=MEDIA)


# ------------------------------------------------------------------ excluir-conta e sincronização
def excluir_conta(s, ctx) -> None:
    db, u, p = ctx["db"], ctx["usuarios"], ctx["postos"]
    E = dict(aba="Edge Functions", modulo="excluir-conta", tela="Perfil · Excluir conta")
    r = http("POST", F_EXCLUIR, {})
    s.check(r.status == 401, obtido=resumo(r, 160), **E, tipo="Segurança · autenticação", cenario="Sem login é recusado", precondicoes="-",
            passos="POST sem token", entrada="-", esperado="HTTP 401", severidade=CRITICA)
    r = http("GET", F_EXCLUIR, token=u["davi"]["token"])
    s.check(r.status == 405, obtido=resumo(r, 120), **E, tipo="Funcional · método", cenario="GET é recusado", precondicoes="-",
            passos="GET", entrada="-", esperado="HTTP 405", severidade=BAIXA)
    davi = u["davi"]
    db.execute("insert into public.favoritos (usuario_id, posto_id) values (%s, %s)", (davi["id"], p["exata"]))
    db.execute("insert into public.avaliacoes (posto_id, usuario_id, nota) values (%s, %s, 3)", (p["rua"], davi["id"]))
    envios_antes = um(db, "select count(*) from public.envios where usuario_id=%s", davi["id"])
    r = http("POST", F_EXCLUIR, {}, token=davi["token"])
    s.check(r.status == 200, obtido=resumo(r, 160), **E, tipo="Funcional · positivo", cenario="Usuário exclui a própria conta",
            precondicoes="davi com envios, favorito e avaliação", passos="POST com token", entrada="-", esperado="HTTP 200", severidade=CRITICA)
    restos = {t: um(db, f"select count(*) from public.{t} where usuario_id=%s", davi["id"])
              for t in ("favoritos", "avaliacoes", "pontos_movimentos", "notificacoes")}
    restos["perfis"] = um(db, "select count(*) from public.perfis where id=%s", davi["id"])
    restos["auth.users"] = um(db, "select count(*) from auth.users where id=%s", davi["id"])
    s.check(all(v == 0 for v in restos.values()), obtido=f"linhas restantes: {restos}", aba="Banco de Dados", modulo="LGPD",
            tela="Exclusão de conta", tipo="Banco · cascata", cenario="Exclusão apaga perfil, avaliações, favoritos, pontos e avisos",
            precondicoes="Conta excluída", passos="Contar linhas do usuário em cada tabela", entrada="-", esperado="Tudo 0", severidade=CRITICA)
    anon = um(db, "select count(*) from public.envios where usuario_id is null and posto_id = any(%s)", list(p.values()))
    s.check(envios_antes > 0 and anon >= envios_antes, obtido=f"envios do davi antes: {envios_antes}; envios sem dono nos postos de teste: {anon}",
            aba="Banco de Dados", modulo="LGPD", tela="Exclusão de conta", tipo="Banco · cascata",
            cenario="Preços enviados continuam no histórico, sem vínculo com a pessoa", precondicoes="Conta excluída",
            passos="Contar envios com usuario_id nulo", entrada="-", esperado="Envios mantidos com usuario_id nulo", severidade=ALTA)
    r = dt.entrar(davi["email"], davi["senha"])
    s.check(r.status == 400, obtido=resumo(r, 120), **E, tipo="Funcional · negativo", cenario="Conta excluída não entra mais",
            precondicoes="Conta excluída", passos="Login", entrada="credenciais antigas", esperado="HTTP 400", severidade=ALTA)
    r = _enviar(davi["token"], p["exata"], -10.5, -59.5, [{"produto_id": 2, "preco": 6.0}])
    s.check(r.status in (401, 403), obtido=resumo(r, 160), **E, tipo="Segurança · sessão", cenario="Token antigo de conta excluída não envia preço",
            precondicoes="Conta excluída", passos="enviar-precos com o token antigo", entrada="-", esperado="HTTP 401/403", severidade=ALTA)


def sincronizacao(s, ctx) -> None:
    from comum import ENV
    E = dict(aba="Edge Functions", modulo="sincronizar-cadastro-anp", tela="Agendamento semanal")
    for desc, cab in (("sem o segredo", {}), ("com segredo errado", {"x-cron-secret": "errado"})):
        r = http("POST", F_SINC, {"uf": "AP"}, cabecalhos=cab)
        s.check(r.status == 401, obtido=resumo(r, 160), **E, tipo="Segurança · autenticação", cenario=f"Chamada {desc} é recusada",
                precondicoes="-", passos="POST", entrada=desc, esperado="HTTP 401", severidade=CRITICA)
    r = http("POST", F_SINC, {"uf": "AP"}, token=ctx["usuarios"]["ana"]["token"])
    s.check(r.status == 401, obtido=resumo(r, 160), **E, tipo="Segurança · autorização", cenario="Usuário comum logado não dispara a sincronização",
            precondicoes="ana logada", passos="POST com token de usuário", entrada="-", esperado="HTTP 401", severidade=ALTA)
    segredo = ENV.get("CRON_SECRET", "")
    r = http("POST", F_SINC, {"uf": "ZZ"}, cabecalhos={"x-cron-secret": segredo})
    s.check(r.status == 422, obtido=resumo(r, 160), **E, tipo="Funcional · validação", cenario="UF inválida é recusada sem chamar a ANP",
            precondicoes="Segredo correto", passos="POST {uf: ZZ}", entrada="ZZ", esperado="HTTP 422", severidade=BAIXA)
    db = ctx["db"]
    antes = db.execute("select count(*), count(*) filter (where ativo) from public.postos where uf='AP'").fetchone()
    t0 = time.time()
    r = http("POST", F_SINC, {"uf": "AP"}, cabecalhos={"x-cron-secret": segredo}, timeout=150)
    depois = db.execute("select count(*), count(*) filter (where ativo), max(sincronizado_em) from public.postos where uf='AP'").fetchone()
    ok = r.status == 200 and isinstance(r.corpo, dict) and r.corpo.get("postos", 0) > 0
    s.check(ok, obtido=f"{resumo(r, 200)}; postos AP antes {antes}, depois {depois[:2]}, sincronizado_em {depois[2]}",
            aba="Integração", modulo="API de Revendedores da ANP", tela="sincronizar-cadastro-anp", tipo="Integração · API externa",
            cenario="Sincronização real de uma UF pequena (Amapá) com a API da ANP", precondicoes="Segredo correto; API da ANP no ar",
            passos="POST {uf: AP} com x-cron-secret; comparar o cadastro antes e depois", entrada="AP",
            esperado="HTTP 200 com a quantidade de postos; cadastro atualizado", severidade=ALTA,
            obs=f"Duração {time.time() - t0:.1f} s. É a mesma rotina que o agendamento roda aos domingos.")
    if ok:
        dif = abs(depois[1] - antes[1])
        s.check(dif <= max(5, antes[1] * 0.1), obtido=f"ativos antes {antes[1]}, depois {depois[1]}", aba="Banco de Dados",
                modulo="Importação ANP", tela="Tabela postos", tipo="Banco · integridade",
                cenario="Sincronização não desativa uma fatia grande do cadastro da UF de uma vez", precondicoes="Sincronização feita",
                passos="Comparar postos ativos do AP", entrada="-", esperado="Variação de até 10%", severidade=ALTA)
