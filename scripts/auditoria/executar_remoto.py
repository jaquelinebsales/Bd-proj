"""
Roda os testes contra o projeto Supabase real.

1. Cria os dados da auditoria (postos e usuários fictícios) e roda os testes que precisam deles.
2. Apaga tudo o que foi criado.
3. Com a base já limpa, roda a integridade dos dados reais e a performance, para que nada fictício entre nas medidas.

Uso: python scripts/auditoria/executar_remoto.py
"""
from __future__ import annotations

import sys
import traceback

import comum
import dados_teste as dt
import t_autenticado as ta
import t_integridade as ti
import t_matriz as tm
import t_performance as tp
import t_seguranca as ts


def _etapas(s, etapas) -> None:
    for nome, f in etapas:
        print(f"\n== {nome}")
        try:
            f()
        except Exception as e:  # noqa: BLE001
            traceback.print_exc()
            s.add(status="BLOCKED", aba="Integração", modulo="Execução da auditoria", tela=nome, tipo="Execução",
                  cenario=f"Etapa '{nome}' interrompida por erro do próprio script de teste",
                  precondicoes="-", passos="-", entrada="-", esperado="Etapa completa",
                  obtido=f"{type(e).__name__}: {e}", severidade=comum.MEDIA,
                  obs="Os testes seguintes desta etapa não rodaram; ver o log da execução.")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    s = comum.Suite("remoto", "R")
    db = comum.conectar_banco()
    print(dt.limpar(db))
    ctx = {"db": db}
    try:
        ctx["postos"] = dt.criar_postos(db)
        ctx["usuarios"] = dt.criar_usuarios(db)
        print("dados de teste criados:", ctx["postos"])
        _etapas(s, [
            ("autenticação", lambda: ta.autenticacao(s, ctx)),
            ("autorização", lambda: ta.autorizacao(s, ctx)),
            ("enviar-precos", lambda: ta.enviar_precos(s, ctx)),
            ("corrigir-posicao", lambda: ta.corrigir_posicao(s, ctx)),
            ("matriz do visitante", lambda: tm.rodar(s, ctx)),
            ("funções", lambda: ts.funcoes(s, ctx, ctx["usuarios"]["ana"]["token"])),
            ("manipulação", lambda: ts.manipulacao(s, ctx)),
            ("exposição", lambda: ts.exposicao(s, ctx)),
            ("excluir-conta", lambda: ta.excluir_conta(s, ctx)),
            ("sincronização", lambda: ta.sincronizacao(s, ctx)),
        ])
    finally:
        msg = dt.limpar(db)
        print("\n" + msg)
        s.check(msg.endswith("restam 0 e 0"), obtido=msg, aba="Integração", modulo="Execução da auditoria", tela="Limpeza",
                tipo="Execução", cenario="Dados de teste apagados do projeto real ao final", precondicoes="Auditoria executada",
                passos="Apagar usuários @auditoria.gasprice.test e postos 99999999*", entrada="-",
                esperado="Nenhum dado de teste restante", severidade=comum.ALTA)
        s.salvar()
    _etapas(s, [("integridade", lambda: ti.rodar(s, ctx)), ("performance", lambda: tp.rodar(s, ctx))])
    s.salvar()
    return 0


if __name__ == "__main__":
    sys.exit(main())
