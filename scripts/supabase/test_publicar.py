"""Testes do publicar.py que não usam rede nem o CLI. Uso: python -m unittest discover -s scripts/supabase -p "test_*.py" """
import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import env_util as eu
import publicar

REF = "abcdefghijklmnopqrst"
ENV_FALSO = f"""SUPABASE_URL=https://{REF}.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_AbCdEf123456
SUPABASE_SECRET_KEY=sb_secret_ZyXwVu987654
SUPABASE_DB_PASSWORD=senha-de-teste
SUPABASE_ACCESS_TOKEN=sbp_0123456789abcdef
CRON_SECRET=uma-senha-longa-de-teste-123456
"""


def rodar(args: list[str], conteudo_env: str | None):
    saida = io.StringIO()
    with tempfile.TemporaryDirectory() as d:
        arq = Path(d) / ".env"
        if conteudo_env is not None:
            arq.write_text(conteudo_env, encoding="utf-8")
        with mock.patch.object(eu, "ARQUIVO_ENV", arq), mock.patch.object(publicar, "achar_cli", return_value="supabase"), \
                mock.patch.object(sys, "argv", ["publicar.py", *args]), contextlib.redirect_stdout(saida):
            codigo = publicar.main()
    return codigo, saida.getvalue()


class TestePublicar(unittest.TestCase):
    def test_sem_env_para_com_mensagem(self):
        codigo, texto = rodar(["--simular"], None)
        self.assertEqual(codigo, 1)
        self.assertIn(".env", texto)

    def test_env_em_branco_lista_o_que_falta(self):
        codigo, texto = rodar(["--simular"], "SUPABASE_URL=https://SEU-PROJETO.supabase.co\nSUPABASE_SECRET_KEY=sb_secret_...\n")
        self.assertEqual(codigo, 1)
        for chave in ("SUPABASE_URL", "SUPABASE_SECRET_KEY", "SUPABASE_ACCESS_TOKEN", "CRON_SECRET"):
            self.assertIn(chave, texto)

    def test_simulacao_lista_os_passos_e_nao_mostra_segredos(self):
        codigo, texto = rodar(["--simular", "--com-dados"], ENV_FALSO)
        self.assertEqual(codigo, 0)
        self.assertIn(REF, texto)
        for nome in publicar.FUNCOES:
            self.assertIn(f"functions deploy {nome}", texto)
        self.assertIn("db push", texto)
        self.assertIn("importar_anp.py", texto)
        for segredo in ("sb_secret_ZyXwVu987654", "senha-de-teste", "sbp_0123456789abcdef", "uma-senha-longa-de-teste-123456"):
            self.assertNotIn(segredo, texto)

    def test_url_fora_do_formato_e_recusada(self):
        codigo, texto = rodar(["--simular"], ENV_FALSO.replace(f"{REF}.supabase.co", "exemplo.com"))
        self.assertEqual(codigo, 1)
        self.assertIn("SUPABASE_URL", texto)


if __name__ == "__main__":
    unittest.main()
