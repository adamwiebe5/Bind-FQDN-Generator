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
    zoneContent=`cat $zoneDir'/'$zoneFile`

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
	    echo '$INCLUDE'" found! Using zone directory: ""$zoneDir"
	  fi

	  currentRecord=`awk '{print $1}' <<< "$z"`
	  recordType=`awk '{print $1}' <<< "$z"`

	  case $currentRecord in

            '$ORIGIN')
              currentZone="${z/\$ORIGIN /}";;

	    *'.') 
	      lastFQDN=`echo ${currentRecord/%?/}`
	      echo ${currentRecord/%?/};;

            '$TTL'|[0-9][0-9][0-9]*|'"'*)
              echo "EXCLUDING: ""$currentRecord" > /dev/null;;

            '@')
	      lastFQDN="$currentZone"
	      echo "$currentZone";;

            'TXT'|'SPF'|'A'|'CNAME'|'MX'|'NS')
	      printf "$lastFQDN""\tRecord Type: ""$recordType\n";;

	    '' )
	      echo "THIS IS A BLANK RECORD, using ""$lastFQDN";;

#	    [^a-zA-Z0-9-]*)
#	      lastRecord=$currentRecord;;
#	      #echo "LAST RECORD: ""$lastRecord";;
	    
	    *)
	      lastFQDN="$currentRecord"'.'"$currentZone"
	      echo "$currentRecord"'.'"$currentZone";;
	  esac
	      
	fi
      done <<< "$zoneContent"
    unset currentZone
  fi

done <<< "$compiledZoneFile"
}

echo '' > /tmp/fqdn-generator.tmp
createNamed
processNamed
rm /tmp/fqdn-generator.tmp
