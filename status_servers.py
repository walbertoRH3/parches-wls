# -*- coding: utf8 -*-
import sys

# Obtener los valores de usuario, contraseña y URL desde los argumentos de la línea de comandos
username = sys.argv[1]
password = sys.argv[2]
url = sys.argv[3]

# Conectar con los valores proporcionados
connect(username, password, url)

# Obtener la lista de servidores
servers = cmo.getServers()

# Imprimir el estado de los servidores
print("    Domain Name:\t" + cmo.getName())
for server in servers:
    state(server.getName(), server.getType())
