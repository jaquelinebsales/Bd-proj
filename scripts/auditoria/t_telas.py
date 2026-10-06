"""
Telas e responsividade: roda app/test_auditoria (cada rota × 7 tamanhos de tela/fonte), como visitante e logado,
no modo demonstração e com a fonte real, e transforma cada caso numa linha da matriz.

Uso: python scripts/auditoria/t_telas.py
"""
from __future__ import annotations

import json
import sys

from comum import ALTA, BAIXA, MEDIA, Suite
from t_automatizados import RAIZ, guardar, rodar

SO_LOGADO = {"/perfil/editar", "/perfil/senha", "/pontos", "/notificacoes"}
SO_VISITANTE = {"/entrar", "/cadastro"}


def executar(s: Suite, logado: bool) -> None:
    modo = "logado" if logado else "visitante"
    cmd = "flutter test test_auditoria --no-pub --update-goldens --dart-define=DEMO=true" + (" --dart-define=DEMO_LOGADO=true" if logado else "")
    r = rodar(cmd, RAIZ / "app", timeout=3600)
    ev = guardar(f"telas_{modo}.txt", r.stdout + r.stderr)
    casos = []
    for linha in r.stdout.splitlines():
        if linha.startswith("AUDITORIA|"):
            casos.append(json.loads(linha.split("|", 1)[1]))
    if not casos:
        s.add(status="BLOCKED", obtido=(r.stdout + r.stderr)[-600:], aba="UI/Telas", modulo="Execução", tela="flutter test",
              tipo="Responsividade", cenario=f"Suíte de telas ({modo})", precondicoes="-", passos=cmd, entrada="-",
              esperado="Casos executados", severidade=ALTA, evidencia=ev)
        return
    for c in casos:
        graves = [e for e in c["erros"] if e["tipo"] in ("estouro", "layout", "exceção")]
        rede = [e for e in c["erros"] if e["tipo"].startswith("rede") or e["tipo"].startswith("ambiente")]
        fonte = c["fonte"]
        tipo = "Acessibilidade · fonte ampliada" if fonte > 1 else ("Responsividade · tablet" if c["largura"] >= 800 else "Responsividade · celular")
        redirecionada = c["rota_final"].split("?")[0] != c["rota"].split("?")[0]
        sev = MEDIA if (c["largura"] >= 360 and fonte <= 1.3) else BAIXA
        if c["largura"] == 320 and fonte == 1:
            sev = MEDIA
        obtido = "; ".join(e["mensagem"][:160] for e in graves) if graves else "Sem estouro de layout nem exceção"
        if rede:
            obtido += f" · {len(rede)} aviso(s) do ambiente de teste ignorados (sem internet e sem plugins nativos)"
        obtido += f" · textos: {' | '.join(c['textos'][:4])}"
        # Rota redirecionada mostra outra tela (Entrar ou Perfil), já medida na própria linha: só entra o teste de redirecionamento
        if not redirecionada:
            s.check(not graves, obtido=obtido, aba="UI/Telas", modulo=c["tela"], tela=c["rota"], tipo=tipo,
                    cenario=f"{c['tela']} ({modo}) em {c['tamanho']} abre sem estouro de layout",
                    precondicoes=f"Modo demonstração, {modo}, fonte Roboto",
                    passos=f"Abrir a rota {c['rota']} com tela de {int(c['largura'])}×{int(c['altura'])} e fonte {int(fonte * 100)}%",
                    entrada="-", esperado="Nenhum 'RenderFlex overflowed', erro de layout ou exceção", severidade=sev,
                    evidencia=c.get("imagem") or ev)
        rota = c["rota"].split("?")[0]
        if c["tamanho"].startswith("Celular 360×800") and fonte == 1:
            if not logado and rota in SO_LOGADO:
                s.check(c["rota_final"] == "/entrar", obtido=f"rota final: {c['rota_final']}", aba="Autenticação", modulo="Rotas protegidas",
                        tela=rota, tipo="Segurança · navegação", cenario=f"Visitante que abre {rota} é levado para Entrar",
                        precondicoes="Sem login", passos=f"Abrir {rota}", entrada="-", esperado="/entrar", severidade=ALTA, evidencia=ev)
            if logado and rota in SO_VISITANTE:
                s.check(c["rota_final"] == "/perfil", obtido=f"rota final: {c['rota_final']}", aba="Autenticação", modulo="Rotas protegidas",
                        tela=rota, tipo="Funcional · navegação", cenario=f"Usuário logado que abre {rota} vai para o Perfil",
                        precondicoes="Logado", passos=f"Abrir {rota}", entrada="-", esperado="/perfil", severidade=BAIXA, evidencia=ev)
            if logado and rota in SO_LOGADO:
                s.check(c["rota_final"].split("?")[0] == rota, obtido=f"rota final: {c['rota_final']}", aba="Autenticação",
                        modulo="Rotas protegidas", tela=rota, tipo="Funcional · navegação", cenario=f"Usuário logado abre {rota}",
                        precondicoes="Logado", passos=f"Abrir {rota}", entrada="-", esperado=rota, severidade=MEDIA, evidencia=ev)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    s = Suite("telas", "T")
    executar(s, logado=False)
    executar(s, logado=True)
    s.salvar()
    return 0


if __name__ == "__main__":
    sys.exit(main())
