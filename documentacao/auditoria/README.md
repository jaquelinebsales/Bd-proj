# Auditoria do gasprice (06/10/2026)

- `auditoria_gasprice.xlsx`: matriz com os 873 testes, um por linha; Dashboard, uma aba por área e a aba **Bugs encontrados**.
- `testes_android_studio.md`: como preparar o Android Studio e executar os 30 casos da aba **Android (manual)**.
- `resultados/*.json`: o registro de cada teste, gravado pelos scripts. A planilha é montada só a partir deles.
- `evidencias/`: imagens das telas com estouro de layout (`telas/`) e dos testes no navegador (`e2e/`).
- `logs/`: saída completa de cada suíte.

## Rodar de novo

Na raiz do projeto, com `py -3.12` (playwright, psycopg e openpyxl instalados) e o `.env` preenchido:

```powershell
cd scripts\auditoria
py -3.12 t_automatizados.py     # análise estática, testes do app, das funções, dos scripts e 103 regras no Postgres local
py -3.12 t_telas.py             # 24 rotas × 7 tamanhos de tela e fonte, visitante e logado
py -3.12 executar_remoto.py     # Supabase real: segurança, Edge Functions, integridade e performance
py -3.12 t_e2e.py               # navegador; antes: servir app/build/web_real em http://127.0.0.1:8790
py -3.12 t_android.py           # casos manuais do Android
py -3.12 gerar_planilha.py; py -3.12 verificar_planilha.py
```

Os testes no Supabase real criam usuários `@auditoria.gasprice.test` e postos com CNPJ `99999999…`, e apagam tudo no fim. Se uma execução for interrompida, limpe com `py -3.12 dados_teste.py limpar`.
