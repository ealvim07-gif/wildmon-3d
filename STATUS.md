# STATUS DO PROJETO (atualize no fim de cada tarefa)

## Versões
- **Estável (main):** commit 263b67f, APK #125. Personagem humano animado, tela inicial, interface limpa.
- **Trabalho (mundo-vivo):** terreno por blocos com colisão, lago, colinas e árvores. Último commit verde conhecido: 1307436 (Validate #150, Build APK #141). Depois dele: c512442 (passo do simulador no workflow), resultado A CONFIRMAR.

## O que funciona (confirmado pelo usuário no celular)
- Tela inicial com botão Iniciar.
- Personagem humano (Quaternius Superhero_Male) com animações Idle, Walk, Jog_Fwd e Sprint, sem T-pose.
- Joystick, corrida contínua e colisão com o terreno (sem afundar).
- Lagos com água; o personagem anda no fundo sem atravessar.
- Carregamento depois do botão Iniciar é lento (a otimizar).

- Câmera em primeira pessoa por padrão (olhos a 1,65 m, constante EYE_HEIGHT_M em game.gd) com botão VISÃO para alternar para terceira pessoa. Confirmado no celular. O simulador mediu modo `first` e olhos a 1,67 m.

## Implementado, NÃO confirmado no celular
- Tarefa 4: textura em estilo pintado (Legends: Arceus), só por código, sem fotos. Chão: paleta mais suave e menos saturada, grão fino e pontinhos reduzidos (constantes GRASS_*, TINT_*, GROUND_TINT, FINE_CONTRAST, SPECKLE_* no topo de world_terrain.gd). Árvores: materiais copiados com luz suave (difusão wrap), sem brilho e com leve tom quente (TREE_SOFT_LIGHT, TREE_NO_SHINE, TREE_TINT em world_trees.gd). Resultado visual A CONFIRMAR no celular; os valores são um primeiro palpite ajustável.
- Tarefa 3: escala das árvores em scripts/world_trees.gd. Cada árvore tem a altura do modelo medida e é escalada para uma altura entre TREE_HEIGHT_MIN_M e TREE_HEIGHT_MAX_M (9 a 15 m), entra no grupo `trees` com a meta `height_m`, e a base é apoiada no chão. Colisão do tronco com raio de 0,35 m reais.

## Problemas conhecidos
- Textura do chão continua procedural (agora com paleta pintada). world_terrain.gd aceita fotos em assets/terrain/grass_albedo.jpg e grass_normal.jpg, se quisermos trocar depois.
- Troncos de alguns pinheiros aparecem inclinados e com galhos nus (parece ser do modelo Pine_1/Pine_2); copas com sombra bem escura (a Tarefa 4 tenta suavizar com luz wrap; A CONFIRMAR).
- Água do lago: manchas azuis de borda recortada; uma parece acima do chão ao redor (suspeita, não medida).
- Mundo limitado a 256 m, com limite de movimento de ±118 m.
- world_terrain.gd calcula a normal de cada vértice com 4 chamadas a height_at (pode pesar no carregamento).

## Última tarefa concluída
Tarefa 1 (simulador no workflow, commit c512442) e Tarefa 2 (primeira pessoa) concluídas e confirmadas no celular.

## Próxima tarefa
Confirmar as Tarefas 3 e 4 (Validate, Build APK, Simulador com 0 árvores fora da escala, e teste no celular). Depois: grama com vento (roadmap item 4) e visual Legends: Arceus (céu, neblina, água do lago).
