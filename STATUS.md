# STATUS DO PROJETO (atualize no fim de cada tarefa)

## Versões
- **Estável (main):** commit 263b67f, APK #125. Personagem humano animado, tela inicial, interface limpa.
- **Trabalho (mundo-vivo):** terreno por blocos com colisão, lago, colinas e árvores. Último commit verde: A CONFIRMAR.

## O que funciona (confirmado pelo usuário no celular)
- Tela inicial com botão Iniciar.
- Personagem humano (Quaternius Superhero_Male) com animações Idle, Walk, Jog_Fwd e Sprint, sem T-pose.
- Joystick, corrida contínua e colisão com o terreno (sem afundar).
- Lagos com água; o personagem anda no fundo sem atravessar.
- Carregamento depois do botão Iniciar é lento (a otimizar).

## Problemas conhecidos
- Textura do chão procedural (ruído), não parece realista.
- Proporções (árvores, personagem, terreno) sem padrão de escala.
- Câmera em terceira pessoa; o usuário quer primeira pessoa.
- Mundo limitado a cerca de 256 m, com limite de movimento de ±118 m.
- Árvores adicionadas pelo usuário: precisam seguir o contrato de escala (PROJECT_RULES.md, seção 2).
- Modo de teste de terreno sem iluminação pode ter ficado ligado: conferir `DEBUG_TERRAIN_UNSHADED`.

## Última tarefa concluída
Nenhuma ainda com as regras novas.

## Próxima tarefa
Instalar o simulador de teste (roadmap item 1).
