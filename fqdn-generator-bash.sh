#!/bin/bash
#
# Usage: ./script.sh [named.conf filepath] [zonefile directory]
# Example: ./script.sh ~/Desktop/named/named.conf ~/Desktop/named/pri/
#
IFS='%'
config=`cat "$1"`
zoneDir=`echo ${2%/}`
confFile=`echo "${1##*\/}"`
confFileDir=`echo ${1%/*.*}`

createNamed () {

printf "Printing compiled zone file to /tmp/fqdn-generator.tmp...\n"
while read i; do

if [[ $i == *'#'* ]]
  then
  i=`echo ${i%#*}`
  i="${i/\#/}"
fi

  if [[ $i == *'include "'* ]]
    then
    currentConfFile=`echo "${i##*\/}"`
    currentConfFile="${currentConfFile/\"\;/}"

    config1=`cat "$confFileDir"'/'"$currentConfFile"`

      while read j; do

      if [[ $j == *'#'* ]]
        then
        j=`echo ${j%#*}`
        j="${j/\#/}"
      fi

	j=`echo ${j%#*}`
	j="${j/\#/}"
  	if [[ $j == *'include "'* ]]
    	  then
    	  currentConfFile=`echo "${j##*\/}"`
    	  currentConfFile="${currentConfFile/\"\;/}"

    	  config2=`cat "$confFileDir"'/'"$currentConfFile"`

        while read h; do

	if [[ $h == *'#'* ]]
	  then
	  h=`echo ${h%#*}`
	  h="${h/\#/}"
	fi

	  h=`echo ${h%#*}`
	  h="${h/\#/}"
          if [[ $h == *'include "'* ]]
            then
            currentConfFile=`echo "${h##*\/}"`
            currentConfFile="${currentConfFile/\"\;/}"

            config3=`cat "$confFileDir"'/'"$currentConfFile"`

          elif [[ $h != '' ]]
	    then
            echo "$h" >> /tmp/fqdn-generator.tmp
          fi

        done <<< "$config2"

 	elif [[ $j != '' ]]
	  then
  	  echo "$j" >> /tmp/fqdn-generator.tmp
  	fi

      done <<< "$config1"

  elif [[ $i != '' ]]
    then
    echo "$i" >> /tmp/fqdn-generator.tmp
  fi
done <<< "$config"

printf "Done!\n"

}

processNamed () {

compiledZoneFile=`cat /tmp/fqdn-generator.tmp`

while read k; do

  if [[ $k == *'zone "'* ]]
    then
    currentZone=`awk '{print $2}' <<< "$k"`
    currentZone="${currentZone/\"/}"
    currentZone="${currentZone/\"/}"
    currentRecord="$currentZone"
  fi

  if [[ $k == *'type '* ]]
    then
    zoneType=`awk '{print $2}' <<< "$k"`
  fi

  if [[ -n $currentZone ]] && [[ $zoneType == 'master;' ]] && [[ $k == *'file "'* ]]
    then
    zoneFile=`awk '{print $2}' <<< "$k"`
    zoneFile="${zoneFile##*\/}"
    zoneFile="${zoneFile/\"\;/}"

    processZone $zoneFile

  fi

done <<< "$compiledZoneFile"
}


processZone () {

zoneContent=`cat $zoneDir'/'$1`

      while read z; do

	if [[ $z != ';'* ]] && [[ $z != '' ]]
	  then

	  if [[ $z == *';'* ]]
	    then
	    z=`echo ${z%;*}`
	    z="${z/\;/}"
	  fi

	  if [[ $z == '$INCLUDE'* ]]
	    then
	    #echo '$INCLUDE'" found! Using zone directory: ""$zoneDir"
	    zoneFile=`awk '{print $2}' <<< "$z"`
	    currentZone=`awk '{print $3}' <<< "$z"`
	    currentZone=${currentZone%.*}
	    #echo ${currentZone%.*}
	    processZone $zoneFile
	  fi

	  if [[ $z != [0-9][0-9][0-9]* ]]
	    then
	    echo 'MATCH'
	  elif [[ $z == *'TXT'* ]] || [[ $z == *'SPF'* ]] || [[ $z == *'MX'* ]] || [[ $z == *'NS'* ]] || [[ $z == *'SRV'* ]] || [[ $z == *'LOC'* ]]
	    then
	    
	    case $z in
	      
	      *'TXT'*)
		recordType="TXT";;

	      *'SPF'*)
		recordType="SPF";;

	      *'MX'*)
		recordType="MX";;

	      *'NS'*)
		recordType="NS";;

	      *'SRV'*)
		recordType="SRV";;

	      *'LOC'*)
		recordType="LOC";;

	      *)
		recordType="A";;
	    esac
#	  else 
#	    recordType="A"
	  fi
	  if [[ $z == *'\$'* ]]
	    then
	echo '$GENERATE FOUND'
	    currentRecord="$GENERATE"
	  fi

	  currentRecord=`awk '{print $1}' <<< "$z"`

	  case $currentRecord in

            '$ORIGIN')
	      if [[ $z == '$ORIGIN '* ]]
		then
		currentZone="${z/\$ORIGIN /}"
	      elif [[ $z == '$ORIGIN	'* ]]
		then
		currentZone="${z/\$ORIGIN	/}"
	      fi
	      currentZone=${currentZone%.*};;

	    *'.') 
	      lastFQDN=`echo ${currentRecord%?.*}`
	      printf "${currentRecord%.*}","$recordType\n";;

            '$TTL'|'$GENERATE'*|'IN'|[0-9][0-9][0-9]*|'"'*|'4W'|'2h)')
              echo "EXCLUDING: ""$currentRecord" > /dev/null;;

            '@')
	      lastFQDN="$currentZone"
	      printf "$currentZone","$recordType\n";;

            'TXT'|'SPF'|'A'|'CNAME'|'DNAME'|'MX'|'NS'|'LOC'|'SRV')
	      recordType=`awk '{print $1}' <<< "$z"`
	      printf "$lastFQDN","$recordType\n";;

	    '' )
	      echo "THIS IS A BLANK RECORD, using ""$lastFQDN" > /dev/null;;

	    *)
	      lastFQDN="$currentRecord"'.'"$currentZone"

#	      if [[ $currentZone == *'in-addr.arpa'* ]]
#  		then
#  		modRecord="$currentRecord"'.'"$currentZone"
#  		modRecord="${modRecord/.in-addr.arpa/}"
#
#  		OIFS=$IFS
#  		IFS=. read w x y z <<<"$modRecord"
#  		printf "$z"'.'"$y"'.'"$x"'.'"$w\n"
#  		IFS=$OIFS
#	      elif [[ $currentZone == *'IN-ADDR.ARPA'* ]]
#  		then
#  		modRecord="$currentRecord"'.'"$currentZone"
#  		modRecord="${modRecord/.IN-ADDR.ARPA/}"
#
#  		OIFS=$IFS
#  		IFS=. read w x y z <<<"$modRecord"
#  		printf "$z"'.'"$y"'.'"$x"'.'"$w\n"
#  		IFS=$OIFS
#	      else
 		printf "$currentRecord"'.'"$currentZone","$recordType\n";;
#	      fi;;

	  esac

	unset recordType
	     
	fi
      done <<< "$zoneContent"
    unset currentZone
}


echo '' > /tmp/fqdn-generator.tmp
createNamed
processNamed
rm /tmp/fqdn-generator.tmp
