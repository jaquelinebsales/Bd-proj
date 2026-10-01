"""Testes de env_util (sem rede). Uso: python -m unittest discover -s scripts/supabase -p "test_*.py" """
import tempfile
import unittest
from pathlib import Path
from urllib.parse import unquote, urlsplit

import env_util as e

REF = "abcdefghijklmnopqrst"


def env(**kw):
    return {k: v for k, v in kw.items()}


class TesteEnv(unittest.TestCase):
    def test_carregar_ignora_comentarios_e_tira_aspas(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / ".env"
            p.write_text('# comentario\nA=1\nB="dois"\nC=tem=igual\nD=senha#com#cerquilha\n\nsem_igual\n', encoding="utf-8")
            r = e.carregar_env(p)
        self.assertEqual(r, {"A": "1", "B": "dois", "C": "tem=igual", "D": "senha#com#cerquilha"})

    def test_arquivo_ausente(self):
        with self.assertRaises(e.ErroEnv):
            e.carregar_env(Path("nao-existe/.env"))

    def test_estado_reconhece_exemplos_e_valores_reais(self):
        self.assertEqual(e.estado("SUPABASE_URL", ""), "vazio")
        self.assertEqual(e.estado("SUPABASE_URL", "   "), "vazio")
        self.assertEqual(e.estado("SUPABASE_URL", "https://SEU-PROJETO.supabase.co"), "exemplo")
        self.assertEqual(e.estado("SUPABASE_SECRET_KEY", "sb_secret_..."), "exemplo")
        self.assertEqual(e.estado("SUPABASE_ACCESS_TOKEN", "sbp_..."), "exemplo")
        self.assertEqual(e.estado("DATABASE_URL", "postgresql://postgres.SEU-PROJETO:SENHA-DO-BANCO@aws-1-REGIAO.pooler.supabase.com:5432/postgres"), "exemplo")
        self.assertEqual(e.estado("DATABASE_URL", "postgresql://postgres.x:[YOUR-PASSWORD]@h:5432/postgres"), "exemplo")
        self.assertEqual(e.estado("SUPABASE_PUBLISHABLE_KEY", "sb_publishable_AbCdEf123456"), "preenchido")
        self.assertEqual(e.estado("SUPABASE_URL", f"https://{REF}.supabase.co"), "preenchido")

    def test_senha_do_banco_pode_terminar_em_reticencias(self):
        self.assertEqual(e.estado("SUPABASE_DB_PASSWORD", "minha-senha..."), "preenchido")

    def test_ref_vem_da_url(self):
        self.assertEqual(e.ref_do_projeto(env(SUPABASE_URL=f"https://{REF}.supabase.co")), REF)
        self.assertEqual(e.ref_do_projeto(env(SUPABASE_URL="https://SEU-PROJETO.supabase.co")), None)
        self.assertEqual(e.ref_do_projeto(env(SUPABASE_URL="https://exemplo.com")), None)
        self.assertEqual(e.ref_do_projeto(env(SUPABASE_PROJECT_REF="zzzzzzzzzzzzzzzzzzzz", SUPABASE_URL=f"https://{REF}.supabase.co")), "zzzzzzzzzzzzzzzzzzzz")

    def test_interpreta_url_do_banco(self):
        r = e.interpretar_url_banco(f"postgresql://postgres.{REF}:segredo123@aws-1-sa-east-1.pooler.supabase.com:5432/postgres")
        self.assertEqual((r["usuario"], r["senha"], r["host"], r["porta"], r["banco"]),
                         (f"postgres.{REF}", "segredo123", "aws-1-sa-east-1.pooler.supabase.com", "5432", "postgres"))

    def test_senha_com_arroba_e_dois_pontos_ainda_funciona(self):
        r = e.interpretar_url_banco("postgresql://u:p@ss:word@host.com:5432/postgres")
        self.assertEqual((r["senha"], r["host"]), ("p@ss:word", "host.com"))

    def test_senha_com_barra_ou_colchete_e_recusada_com_dica(self):
        for senha in ("ab/cd", "ab#cd", "[YOUR-PASSWORD]", "50%off"):
            with self.subTest(senha=senha), self.assertRaises(e.ErroEnv) as c:
                e.interpretar_url_banco(f"postgresql://u:{senha}@host.com:5432/postgres")
            self.assertIn("SUPABASE_DB_PASSWORD", str(c.exception))

    def test_url_fora_do_formato(self):
        with self.assertRaises(e.ErroEnv):
            e.interpretar_url_banco("mysql://u:p@h/db")

    def test_usa_database_url_quando_preenchida(self):
        url = f"postgresql://postgres.{REF}:abc@host.pooler.supabase.com:5432/postgres"
        r, origem = e.resolver_database_url(env(DATABASE_URL=url), consultar=lambda *a: 1 / 0)
        self.assertEqual(r, url)
        self.assertIn(".env", origem)

    def test_monta_url_pela_api_com_senha_codificada(self):
        senha = "p@ss:w/rd#1 %"
        chamadas = []

        def falsa(ref, token):
            chamadas.append((ref, token))
            return [
                {"database_type": "READ_REPLICA", "db_host": "replica", "db_user": "x"},
                {"database_type": "PRIMARY", "db_host": "aws-1-sa-east-1.pooler.supabase.com", "db_user": f"postgres.{REF}", "db_name": "postgres"},
            ]

        url, origem = e.resolver_database_url(
            env(SUPABASE_URL=f"https://{REF}.supabase.co", SUPABASE_DB_PASSWORD=senha, SUPABASE_ACCESS_TOKEN="sbp_abcdef123456",
                DATABASE_URL="postgresql://postgres.SEU-PROJETO:SENHA-DO-BANCO@aws-1-REGIAO.pooler.supabase.com:5432/postgres"),
            consultar=falsa)
        self.assertEqual(chamadas, [(REF, "sbp_abcdef123456")])
        partes = urlsplit(url)
        self.assertEqual(partes.hostname, "aws-1-sa-east-1.pooler.supabase.com")
        self.assertEqual(partes.port, 5432)
        self.assertEqual(unquote(partes.username), f"postgres.{REF}")
        self.assertEqual(unquote(partes.password), senha)
        self.assertIn("API", origem)

    def test_lista_o_que_falta(self):
        with self.assertRaises(e.ErroEnv) as c:
            e.resolver_database_url(env(SUPABASE_URL="https://SEU-PROJETO.supabase.co"), consultar=lambda *a: [])
        msg = str(c.exception)
        for esperado in ("SUPABASE_DB_PASSWORD", "SUPABASE_ACCESS_TOKEN", "SUPABASE_URL"):
            self.assertIn(esperado, msg)

    def test_resposta_vazia_da_api(self):
        with self.assertRaises(e.ErroEnv):
            e.resolver_database_url(
                env(SUPABASE_URL=f"https://{REF}.supabase.co", SUPABASE_DB_PASSWORD="x", SUPABASE_ACCESS_TOKEN="sbp_abcdef123456"),
                consultar=lambda *a: [])

    def test_mascara_segredos_e_a_senha_da_url(self):
        cfg = env(SUPABASE_SECRET_KEY="sb_secret_ABCDEF123456", SUPABASE_DB_PASSWORD="minha-senha-forte",
                  DATABASE_URL="postgresql://u:outra-senha@h.com:5432/postgres")
        texto = "falhou com sb_secret_ABCDEF123456 e minha-senha-forte e outra-senha"
        self.assertEqual(e.mascarar(texto, cfg), "falhou com *** e *** e ***")


if __name__ == "__main__":
    unittest.main()
