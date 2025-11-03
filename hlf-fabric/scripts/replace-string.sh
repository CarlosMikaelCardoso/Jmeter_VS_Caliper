#!/bin/bash

# Verifica se o usuário forneceu os argumentos necessários
if [ "$#" -ne 3 ]; then
    echo "Uso: $0 <diretorio> <string_antiga> <string_nova>"
    echo "Exemplo: $0 /home/user/projeto foo bar"
    exit 1
fi

# Atribui os argumentos a variáveis
DIRETORIO="$1"
STRING_ANTIGA="$2"
STRING_NOVA="$3"

# Verifica se o diretório existe
if [ ! -d "$DIRETORIO" ]; then
    echo "Erro: O diretório '$DIRETORIO' não existe."
    exit 1
fi

# Executa a substituição em todos os arquivos recursivamente
find "$DIRETORIO" -type f -exec sed -i "s/$STRING_ANTIGA/$STRING_NOVA/g" {} +

echo "Substituição concluída!"