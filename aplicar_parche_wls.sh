#!/bin/bash

usuario=$(whoami)

echo "========================"
echo " Aplicando Parches WLS "
echo "========================"
echo

echo "Buscando dominios en el servidor, un momento por favor........."
echo

busqueda_dominios=$(find / -iname fileRealm.properties 2>/dev/null)

while IFS= read -r dominio; do
    echo

    DOMAIN_HOME=$(dirname "$dominio")
    export DOMAIN_HOME
    nombre_dominio=$(basename "$DOMAIN_HOME")
    ruta=$(echo "$DOMAIN_HOME" | cut -d'/' -f2 | awk '{print "/"$1}')
    ORACLE_HOME=$(dirname "$(find "$ruta" -iname domain-registry.xml 2>/dev/null)")
    export ORACLE_HOME

    echo
    echo "====================="
    echo "Dominios Encontrados:"
    echo "====================="
    echo
	echo "$DOMAIN_HOME"
    echo 
    echo "=========================================================="
    echo "Iniciando Aplicacion de Parches en Dominio $nombre_dominio"
    echo "=========================================================="
    echo

    echo "Validando version de opatch........................"
    echo
    version_req_opatch="13.9.4.2.13"
    echo
    echo "Version requerida de opatch:$version_req_opatch"

    version=$($ORACLE_HOME/OPatch/opatch version 2>/dev/null | grep "OPatch Version" | awk -F': ' '{print $2}')

    if [[ "$(printf '%s\n' "$version_req_opatch" "$version" | sort -V | head -n1)" == "$version_req_opatch" ]]; then
        echo "Patch está en la versión requerida: $version"
    else
        echo "Versión de OPatch no cumple con la requerida: $version"
        echo
        echo "Actualizando OPatch, espere por favor..."
        echo

        DIR="/home/$usuario/parches/OPatch/"
        for archivo in "$DIR"/*.zip; do
            echo "Descomprimiendo $archivo..."
            unzip -o "$archivo" -d "$DIR"
        done
  echo "====================="
  echo " Actualizando OPatch "
  echo "====================="
  echo
        source /home/$usuario/.bash_profile
        java -jar $DIR/6880880/opatch_generic.jar -silent oracle_home=$ORACLE_HOME
        echo
        echo "Version actual:"
        echo
        $ORACLE_HOME/OPatch/opatch version
        echo
        echo "Version Requerida"
        echo
        echo "$version_req_opatch"
        echo
    fi
	echo
	echo "=============================="
	echo "Generando Respaldo de Binarios"
  	echo "=============================="
  	echo

        tar -czvf /home/$usuario/"$nombre_dominio".tar.gz $ORACLE_HOME

	
	WLST="$ORACLE_HOME/oracle_common/common/bin/wlst.sh"
	cd "$DOMAIN_HOME/servers/AdminServer/logs/"
        busqueda=$(grep -ir "listening on" | head -n 1)
        url=$(echo "$busqueda" | grep "listening on" | grep -oE 'listening on [^ ]+:[0-9]+ for' | sort | uniq | sed 's/listening on //;s/ for//' | awk 'NR==1')
	username=$(grep username "$DOMAIN_HOME"/servers/AdminServer/security/boot.properties | awk -F '=' '{gsub(/\\$/, "", $2); print $2 "="}')
	password=$(grep password "$DOMAIN_HOME"/servers/AdminServer/security/boot.properties | awk -F '=' '{gsub(/\\$/, "", $2); print $2 "="}')
	$WLST <<EOF > /home/$usuario/"$nombre_dominio"_conn.txt
domain = "$DOMAIN_HOME"
service = weblogic.security.internal.SerializedSystemIni.getEncryptionService(domain)
encryption = weblogic.security.internal.encryption.ClearOrEncryptedService(service)
print("username:%s" % encryption.decrypt("$username"))
print("password:%s" % encryption.decrypt("$password"))
print("url=t3://$url")
disconnect()
exit()
EOF
	archivo="/home/$usuario/"$nombre_dominio"_conn.txt"
	username=$(grep '^username:' "$archivo" | cut -d':' -f2)
	password=$(grep '^password:' "$archivo" | cut -d':' -f2)
	url=$(grep '^url=' "$archivo" | cut -d'=' -f2)


	echo
	echo "================================================="
	echo "	Verificando El Estatus de los Servicios de WLS "
  	echo "================================================="
  	echo
	 logfile="/home/$usuario/server_status.log"
	 "$WLST" "/home/$usuario/status_servers.py" "$username" "$password" "$url" | sed '1,14d' > "$logfile"
	 cat "$logfile"
	echo

       echo -e "\n"
       echo "=============================================================================="
       echo "                              Bajando Servicios	                           "
       echo "=============================================================================="

                servers=$(cat "$logfile" | grep -o '"[^"]*"' | sed 's/"//g' | sort -r)

                for server in $servers ; do

                    "$WLST" <<EOF
connect('$username','$password','$url')
shutdown('$server', 'Server', force='true')
exit()
EOF
                done
	cd $DOMAIN_HOME/bin
	./stopNodeManager.sh
	echo 
	echo "=============================="
	echo "	   Aplicando Parches        "
	echo "=============================="
	echo
BASE_DIR="/home/$usuario/parches"

for dir in parches_genericos parches_trimestrales; do
    full_dir="${BASE_DIR}/${dir}"
    echo "Revisando directorio: $full_dir"

    if [[ -d "$full_dir" ]]; then
        for zip in "$full_dir"/*.zip; do
            [[ -f "$zip" ]] || continue

            echo " En el directorio '$dir' se encontró el parche: $(basename "$zip")"
	    echo "Descomprimiendo software de parche"
            unzip -q "$zip" -d "$full_dir"

            if [[ "$dir" == "parches_genericos" ]]; then
                for patch_dir in "$full_dir"/*/; do
                    [[ -d "$patch_dir" ]] || continue
                    if [[ -f "$patch_dir/OPatch/opatch" || -f "$patch_dir/opatch" ]]; then
                        echo " Aplicando parche en: $patch_dir"
                        $ORACLE_HOME/./opatch apply -silent -oh "$ORACLE_HOME" -invPtrLoc "$ORACLE_HOME/oraInst.loc" <<< "y"
                    fi
                done
            elif [[ "$dir" == "parches_trimestrales" ]]; then
                for spb_dir in "$full_dir"/WLS_SPB*/; do
                    [[ -d "$spb_dir" ]] || continue
                    spbat_path="$spb_dir/tools/spbat/generic/SPBAT/spbat.sh"
                    if [[ -f "$spbat_path" ]]; then
                        echo " Ejecutando SPBAT en: $spbat_path"
                        sh "$spbat_path" -phase apply -oracle_home "$ORACLE_HOME"
                    else
                        echo " SPBAT no encontrado en $spbat_path"
                    fi
                done
            fi
        done
    else
        echo " El directorio $full_dir no existe."
    fi
done			
       echo -e "\n"
       echo "=============================================================================="
       echo "                              Iniciando Componentes                           "
       echo "=============================================================================="
	
		echo
                dominio_inicio=$(cat dominios.txt)
                cd "$DOMAIN_HOME"/bin
               nohup ./startWebLogic.sh > /dev/null 2>&1 &
                sleep 1m
		nohup ./startNodeManager.sh > /dev/null 2>&1 &
		sleep 1m

                servers=$(cat "$logfile" | grep -o '"[^"]*"' | sed 's/"//g' | sort -r)

                for server in $servers ; do

                    "$WLST" <<EOF
connect('$username','$password','$url')
start('$server', 'Server')
exit()
EOF
		done
	echo
	echo "=================================================="
	echo "Verificando El Estatus de los Servidores Manejados"
  	echo "=================================================="
  	echo
	 logfile="/home/$usuario/server_status.log"
	 "$WLST" "/home/$usuario/status_servers.py" "$username" "$password" "$url" | sed '1,14d' > "$logfile"
	 cat "$logfile"
	echo

done <<< "$busqueda_dominios"
