# WILDMON 3D — REGRAS DO PROJETO

**Leia este arquivo e o STATUS.md inteiros ANTES de qualquer tarefa. Este arquivo só pode ser alterado se o usuário pedir.**

## 1. Visão do jogo
- Jogo de exploração 3D em **Godot 4.4.1 (GL Compatibility)** para **Android**.
- Estilo visual: **Pokémon Legends: Arceus** — mundo aberto *estilizado e bonito*, **não fotorrealista**. Campos amplos, colinas suaves, lagos, árvores, grama que balança com o vento, céu com ciclo de dia e noite, neblina leve de distância, cores vivas e harmoniosas.
- Câmera: **primeira pessoa por padrão** (olhos a 1,65 m), com botão para alternar para terceira pessoa.
- Mundo: aberto e procedural, **sem parede invisível**. Meta futura: terreno gerado em volta do jogador conforme ele anda (streaming de blocos).
- Criaturas (Wildmon): **só depois**. Não adicionar agora.

## 2. Contrato de escala e dados (o simulador testa isto)
- 1 unidade = 1 metro. Jogador: 1,8 m de altura, olhos a 1,65 m, anda a 4,5 m/s, corre a 7 m/s.
- Árvores: 6 a 18 m. Pedras: 0,5 a 3 m. Grama: 0,2 a 0,5 m.
- Toda árvore entra no grupo `trees` e tem a meta `height_m` (altura em metros).
- A câmera do jogador entra no grupo `player_camera` e tem a meta `mode` = `"first"` ou `"third"`.
- O terreno expõe `height_at(x, z)`. A planície inicial (raio de 70 m) é totalmente plana.
- O jogador nunca fica abaixo do chão, nunca atravessa o terreno e nunca fica preso.
- Assets: apenas CC0 ou MIT, com a licença registrada em `assets/LICENSES.md`.
- Limites para celular: texturas até 1024 px, modelos até 15 mil triângulos, sombras só perto do jogador.

## 3. Situação de trabalho (limites reais)
- O usuário trabalha **só pelo celular** e testa o APK no aparelho. **Você não vê o jogo.**
- Por isso: nunca afirme como algo "ficou bonito" ou "está correto visualmente". Diga apenas o que foi medido (logs, simulador, workflows).
- Branches: `main` = versão estável (**NÃO tocar**), `backup-protagonista-ok` (**NÃO tocar**), `mundo-vivo` = **único lugar de trabalho**.

## 4. Regras obrigatórias (cada uma vem de um erro que já aconteceu)
1. Antes de editar, **leia os arquivos** envolvidos e cite as linhas que vai mudar. Não escreva código às cegas.
2. **Uma tarefa por vez**, no máximo 3 arquivos. Sem refatoração e sem mudar o que não foi pedido.
3. Nunca faça commit em `main`. Só em `mundo-vivo`.
4. Depois de cada commit, **espere** o Validate, o Build APK e o Simulador. Só diga "concluído" se os três estiverem verdes. Se não conseguir ver o resultado, diga isso e peça ao usuário.
5. Se algo ficar vermelho: leia o log, cite a linha exata do erro, corrija **uma coisa** e espere de novo. Depois de 2 falhas seguidas, **pare** e explique o que sabe e o que não sabe.
6. Não empilhe commits sem verificar o anterior.
7. **Não adivinhe causas visuais.** Adicione primeiro um log ou diagnóstico mensurável, depois corrija.
8. Proibido: inventar resultados, usar "provavelmente" como se fosse fato, criar scripts de teste frágeis que derrubem o Validate, deixar o jogo em modo de teste (ex.: terreno sem iluminação) no commit final.
9. Qualquer ajuste visual deve ficar em uma constante nomeada no topo do arquivo, para o usuário poder alterar à mão.

## 5. Formato fixo do relatório final de cada tarefa
- **Feito:** o que mudou, em 3 linhas.
- **Arquivos alterados:** lista.
- **Commit e build:** números.
- **Workflows:** Validate / Build APK / Simulador, cada um verde ou vermelho (com o link).
- **Evidência:** linhas do log do simulador que provam o resultado.
- **Não testado:** o que só o usuário pode confirmar no celular.
- **Checklist para o celular:** o que o usuário deve ver.
- Atualize o `STATUS.md` no mesmo commit.

## 6. Definição de pronto
Uma tarefa só está pronta quando (a) os três workflows estão verdes, (b) o simulador não tem falhas novas e (c) o usuário confirmou no celular.

## 7. Roadmap (ordem fixa, não pule etapas)
1. Instalar o simulador (`scripts/sim_test.gd` + passo no workflow).
2. Câmera em primeira pessoa com alternância para terceira.
3. Escala e árvores conforme o contrato da seção 2.
4. Texturas de foto CC0 (Poly Haven / ambientCG) + grama com vento.
5. Estilo Legends Arceus: céu, neblina, paleta de cores, vegetação.
6. Mundo aberto com streaming de blocos.
7. Dia e noite, clima.
8. Criaturas (somente depois).
