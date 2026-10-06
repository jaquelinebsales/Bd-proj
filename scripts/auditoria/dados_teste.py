"""
Dados de teste da auditoria no projeto Supabase real, isolados dos dados de verdade.

- Postos fictícios: CNPJ começando por 99999999, nome "POSTO AUDITORIA ...", município "Auditoria" (RO).
- Usuários fictícios: e-mails em @auditoria.gasprice.test (domínio reservado .test, nenhum e-mail é enviado).

`limpar()` apaga tudo o que tiver essas marcas, inclusive o que sobrar de uma execução interrompida.
Uso direto: python scripts/auditoria/dados_teste.py limpar
"""
from __future__ import annotations

import secrets
import sys

import comum

DOMINIO = "auditoria.gasprice.test"
CNPJ = "99999999"
# Pontos no interior de Rondônia, longe de postos reais
POSTOS = {
    "exata": dict(cnpj="99999999000101", nome="POSTO AUDITORIA EXATA LTDA", lat=-10.500000, lon=-59.500000, precisao="exata", ativo=True),
    "rua": dict(cnpj="99999999000202", nome="POSTO AUDITORIA RUA LTDA", lat=-10.600000, lon=-59.600000, precisao="rua", ativo=True),
    "sem_local": dict(cnpj="99999999000303", nome="POSTO AUDITORIA SEM LOCAL LTDA", lat=None, lon=None, precisao="nenhuma", ativo=True),
    "inativo": dict(cnpj="99999999000404", nome="POSTO AUDITORIA INATIVO LTDA", lat=-10.700000, lon=-59.700000, precisao="exata", ativo=False),
    "cidade": dict(cnpj="99999999000505", nome="POSTO AUDITORIA CEP CIDADE LTDA", lat=-10.800000, lon=-59.800000, precisao="cep_cidade", ativo=True),
}
USUARIOS = ["ana", "bruno", "carla", "davi", "nao_confirmado", "banido", "bloqueado"]


def criar_postos(db) -> dict[str, int]:
    ids = {}
    for chave, p in POSTOS.items():
        loc = f"SRID=4326;POINT({p['lon']} {p['lat']})" if p["lat"] is not None else None
        r = db.execute(
            """insert into public.postos (cnpj, razao_social, nome_exibicao, bandeira, endereco, bairro, municipio, uf, cep,
                                         localizacao, localizacao_fonte, ativo, precisao_localizacao)
               values (%s, %s, %s, 'Bandeira branca', 'Rodovia da Auditoria, km 1', 'Teste', 'Auditoria', 'RO', '76800000',
                       %s::extensions.geography, %s, %s, %s)
               returning id""",
            (p["cnpj"], p["nome"], p["nome"].replace(" LTDA", "").title(), loc, "anp" if loc else None, p["ativo"], p["precisao"]),
        ).fetchone()
        ids[chave] = r[0]
    # Preço de referência oficial no posto exato: base para o teste de desvio de 20%
    db.execute("""insert into public.precos_atuais (posto_id, produto_id, preco, fonte, situacao, atualizado_em, ultimo_confiavel)
                  values (%s, 1, 6.000, 'anp', 'oficial', now() - interval '3 days', 6.000)""", (ids["exata"],))
    # Uma linha da auditoria em cada tabela pública ligada ao posto: alvo das tentativas de alteração e exclusão
    db.execute("insert into public.posto_produtos (posto_id, produto_id, bicos) values (%s, 1, 2), (%s, 3, 2)", (ids["exata"], ids["exata"]))
    db.execute("insert into public.precos_anp (posto_id, produto_id, data_coleta, preco) values (%s, 3, date '2024-01-01', 4.200)", (ids["exata"],))
    db.execute("""insert into public.precos_estimados (posto_id, produto_id, preco, margem, distancia_km)
                  values (%s, 2, 6.200, 0.29, 12.0)""", (ids["exata"],))
    db.execute("""insert into public.previsoes (uf, municipio, produto_id, semana, preco_previsto, modelo)
                  values ('RO', 'Auditoria', 1, date_trunc('week', now())::date, 6.100, 'auditoria')""")
    return ids


def criar_usuarios(db) -> dict[str, dict]:
    """Cria os usuários pela API de administração do Auth (sem e-mail enviado) e devolve id, e-mail e senha."""
    usuarios = {}
    sufixo = secrets.token_hex(3)
    for nome in USUARIOS:
        email = f"{nome}.{sufixo}@{DOMINIO}"
        senha = "Aud1t-" + secrets.token_urlsafe(12)
        r = comum.http("POST", "/auth/v1/admin/users", {
            "email": email, "password": senha, "email_confirm": nome != "nao_confirmado",
            "user_metadata": {"nome": f"Auditoria {nome.replace('_', ' ').title()}"},
        }, chave=comum.SECRETA, token=comum.SECRETA)
        if r.status not in (200, 201):
            raise RuntimeError(f"não consegui criar o usuário de teste {nome}: {comum.resumo(r)}")
        usuarios[nome] = {"id": r.corpo["id"], "email": email, "senha": senha}
    db.execute("update public.perfis set banido = true where id = %s", (usuarios["banido"]["id"],))
    db.execute("update public.perfis set bloqueado_ate = now() + interval '7 days' where id = %s",
               (usuarios["bloqueado"]["id"],))
    return usuarios


def entrar(email: str, senha: str) -> comum.Resp:
    return comum.http("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": senha})


def limpar(db=None) -> str:
    db = db or comum.conectar_banco()
    ids_usuarios = [r[0] for r in db.execute("select id from auth.users where email like %s", (f"%@{DOMINIO}",))]
    ids_postos = [r[0] for r in db.execute("select id from public.postos where cnpj like %s", (CNPJ + "%",))]
    # Envios e itens ficam com usuario_id nulo quando a conta some (regra de LGPD); apaga pelos postos de teste
    if ids_postos:
        db.execute("delete from public.pontos_movimentos where envio_item_id in "
                   "(select id from public.envio_itens where posto_id = any(%s))", (ids_postos,))
        db.execute("delete from public.postos where id = any(%s)", (ids_postos,))
    if ids_usuarios:
        db.execute("delete from public.correcoes_posicao where usuario_id = any(%s)", (ids_usuarios,))
        db.execute("delete from auth.users where id = any(%s)", (ids_usuarios,))
    db.execute("delete from public.parametros where chave like 'auditoria%%'")
    db.execute("delete from public.previsoes where municipio = 'Auditoria'")
    sobra_u = db.execute("select count(*) from auth.users where email like %s", (f"%@{DOMINIO}",)).fetchone()[0]
    sobra_p = db.execute("select count(*) from public.postos where cnpj like %s", (CNPJ + "%",)).fetchone()[0]
    return f"apagados {len(ids_usuarios)} usuários e {len(ids_postos)} postos de teste; restam {sobra_u} e {sobra_p}"


if __name__ == "__main__":
    if sys.argv[1:] == ["limpar"]:
        print(limpar())
