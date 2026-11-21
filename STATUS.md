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

## Implementado, NÃO confirmado no celular
- Tarefa 2: câmera em primeira pessoa por padrão (olhos a 1,65 m, constante EYE_HEIGHT_M em game.gd) com botão VISÃO para alternar para terceira pessoa. A câmera está no grupo `player_camera` com meta `mode`.

## Problemas conhecidos
- Textura do chão procedural (ruído), não parece realista. world_terrain.gd já aceita fotos em assets/terrain/grass_albedo.jpg e grass_normal.jpg.
- Proporções das árvores sem padrão de escala (árvores vêm de scripts/world_trees.gd; contrato em PROJECT_RULES.md, seção 2).
- Mundo limitado a 256 m, com limite de movimento de ±118 m.
- world_terrain.gd calcula a normal de cada vértice com 4 chamadas a height_at (pode pesar no carregamento).

## Última tarefa concluída
Nenhuma ainda com as regras novas. Tarefa 1 (simulador no workflow) feita no commit c512442, resultado A CONFIRMAR. Tarefa 2 (primeira pessoa) escrita, A CONFIRMAR após Validate, Build APK, Simulador e teste no celular.

## Próxima tarefa
Confirmar a Tarefa 2. Depois: Tarefa 3, escala e árvores (precisa de scripts/world_trees.gd e de um print das árvores).
