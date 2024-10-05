#!/bin/bash
ZABBIX_API_URL="http://localhost/zabbix/api_jsonrpc.php"  # Cambia esto por tu URL de Zabbix

# Obtener el token de autenticación
AUTH_TOKEN=$(curl -s -X POST -H 'Content-Type: application/json' -d '{
  "jsonrpc": "2.0",
  "method": "user.login",
  "params": {
    "username": "Admin",
    "password": "zabbix"
  },
  "id": 1,
  "auth": null
}' $ZABBIX_API_URL | jq -r '.result')

[[ -z "$AUTH_TOKEN" ]] && exit 1

# Obtener todos los hosts y procesar
curl -s -X POST -H 'Content-Type: application/json' -d '{
  "jsonrpc": "2.0",
  "method": "host.get",
  "params": {
    "output": ["hostid"]
  },
  "id": 2,
  "auth": "'"$AUTH_TOKEN"'"
}' $ZABBIX_API_URL | jq -c '.result[]' | while read -r host; do
  hostid=$(echo "$host" | jq -r '.hostid')

  # Obtener triggers del host
  TRIGGERS=$(curl -s -X POST -H 'Content-Type: application/json' -d '{
    "jsonrpc": "2.0",
    "method": "trigger.get",
    "params": {
      "hostids": "'"$hostid"'",
      "output": ["triggerid", "description"],
      "filter": {
        "description": ["No SNMP data collection", "Device is unreachable"]
      }
    },
    "id": 3,
    "auth": "'"$AUTH_TOKEN"'"
  }' $ZABBIX_API_URL | jq -c '.result[]?')

  # Filtrar los triggers
  trigger_no_snmp=$(echo "$TRIGGERS" | jq -r 'select(.description == "No SNMP data collection") | .triggerid')
  trigger_unreachable=$(echo "$TRIGGERS" | jq -r 'select(.description == "Device is unreachable") | .triggerid')

  # Verificar si ambos triggers existen
  if [[ -n "$trigger_no_snmp" && -n "$trigger_unreachable" ]]; then
    # Verificar si la dependencia ya existe
    DEPENDENCIES=$(curl -s -X POST -H 'Content-Type: application/json' -d '{
      "jsonrpc": "2.0",
      "method": "trigger.get",
      "params": {
        "triggerids": "'"$trigger_no_snmp"'",
        "output": ["triggerid"],
        "selectDependencies": ["triggerid"],
        "filter": {
          "triggerid": "'"$trigger_unreachable"'"
        }
      },
      "id": 4,
      "auth": "'"$AUTH_TOKEN"'"
    }' $ZABBIX_API_URL | jq -r '.result[]? | .triggerid')

    # Si no existe la dependencia, agregarla
    if [[ -z "$DEPENDENCIES" ]]; then
      curl -s -X POST -H 'Content-Type: application/json' -d '{
        "jsonrpc": "2.0",
        "method": "trigger.update",
        "params": {
          "triggerid": "'"$trigger_no_snmp"'",
          "dependencies": [
            {
              "triggerid": "'"$trigger_unreachable"'"
            }
          ]
        },
        "id": 5,
        "auth": "'"$AUTH_TOKEN"'"
      }' $ZABBIX_API_URL
    fi
  fi
done

# Cerrar la sesión
curl -s -X POST -H 'Content-Type: application/json' -d '{
  "jsonrpc": "2.0",
  "method": "user.logout",
  "params": [],
  "id": 6,
  "auth": "'"$AUTH_TOKEN"'"
}' $ZABBIX_API_URL



#El codigo recorre los hosts y genera dependencia de No SNMP data collection 
# con Device is unrechable
