#!/bin/bash
#
# Usage: ./script.sh [named.conf filepath] [zonefile directory]
# Example: ./script.sh ~/Desktop/named/named.conf ~/Desktop/named/zonefiles/
#
#	The above example will send the output to the screen
# 	if you wish to keep the results, simply redirect it to a CSV file
#
# Example: ./script.sh ~/Desktop/named/named.conf ~/Desktop/named/zonefiles/ > ~/Desktop/fqdn-out.csv
#

# Setting Internal Field Separator so Bash recognizes multiple spaces/tabs
IFS='%'

# Reading named.conf (First argument supplied to script)
config=`cat "$1"`

# Setting zonefile directory and also stripping off any trailing slashes
zoneDir=`echo ${2%/}`

# Setting current named.conf filename
confFile=`echo "${1##*\/}"`

# Setting named.conf directory and stripping off supplied filename (We need the directory where named.conf files exist)
confFileDir=`echo ${1%/*.*}`




# Creating function which compiles all named.conf files into 1 configuration file
# this is done to accomodate any includes/complicated configuration which may include multiple views

createNamed () {

printf "Printing compiled zone file to /tmp/fqdn-generator.tmp...\n"
while read i; do


# Checking if the current line contains a comment so we can remove it, we 
# check if a # exists FIRST before attempting to remove a comment that may not exist
# as the attempt to remove a non-existent comment is very taxing

if [[ $i == *'#'* ]]
  then
  # Removing everything after the last #
  i=`echo ${i%#*}`

  # Removing all #
  i="${i/\#/}"
# This will also remove trailing comments
elif [[ $i == *'//'* ]]
  then
  # Removing everything after the last //
  i=`echo ${i%//*}`

  # Removing all //
  i="${i/\/\//}"

# This will also remove trailing comments
fi



  # Checking to see if an include statement exists
  # These duplicate include checks are nested due to stateful restraints

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
	    # After determining the current line is not a comment, or an include statement
	    # we write it to a temporary file to be used later
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


# Creating the function which processes the compiled zone.conf file

# named.conf processing is split into two functions, this allows INCLUDE 
# directives found within the zone file to be processed

processNamed () {

compiledZoneFile=`cat /tmp/fqdn-generator.tmp`

while read k; do


  # Checking to see if a zone exists, if found. Sets the $currentZone

  if [[ $k == *'zone "'* ]]
    then
    currentZone=`awk '{print $2}' <<< "$k"`
    currentZone="${currentZone/\"/}"
    currentZone="${currentZone/\"/}"
    currentRecord="$currentZone"
  fi


  # Checking the zone type (We only care about master zones, as we wont have
  # a zone file for a slave zone)

  if [[ $k == *'type '* ]]
    then
    zoneType=`awk '{print $2}' <<< "$k"`
  fi


  # If $currentZone equals SOMETHING and this is a Master zone and this zone contains a zonefile
  # we can process the zone!

  if [[ -n $currentZone ]] && [[ $zoneType == 'master;' ]] && [[ $k == *'file "'* ]]
    then
    zoneFile=`awk '{print $2}' <<< "$k"`
    zoneFile="${zoneFile##*\/}"
    zoneFile="${zoneFile/\"\;/}"

    processZone $zoneFile

  fi

done <<< "$compiledZoneFile"
}



# Creating function to do actual zonefile processing.
# This function will do the actual outputing of FQDNs
# everything up to this point has been prep for the big moment

processZone () {

zoneContent=`cat $zoneDir'/'$1`

      while read z; do

	
	# Checking to make sure this line is not a comment or blank

	if [[ $z != ';'* ]] && [[ $z != '' ]]
	  then


	  # Like before, we only try to remove trailing comments if
	  # a "comment" character exists in the line

	  if [[ $z == *';'* ]]
	    then
	    z=`echo ${z%;*}`
	    z="${z/\;/}"
	  fi


	# Checking to see if the following lines are related to the SOA
	# The SOA has special values which dont exists anywhere else
	# Its best we get them out of the way now

	if [[ $z == *'SOA'* ]]
	  then
	  soaRecord=true
	  lastFQDN="$currentZone"
	fi


	# A number followed by a closing parenthesis would indicate the end of the SOA

	if [[ $z == *[0-9]*')'* ]]
	  then
	  soaRecord=false
	fi


	  # We can now begin the zonefile processing once we are past the SOA

	  if [[ $soaRecord != true ]]
	    then


	  # If we run into a INCLUDE directive, we will figure out what zonefile
	  # we need to go find, then we reference this same function using the
	  # zonefile as an argument to the function. This will create a new process
	  # and return to the same location it was at, once it is done.
	  # This allow inifinite* nesting of includes and should have been implemented
	  # in the processNamed function (But I'm lazy)

	  if [[ $z == '$INCLUDE'* ]]
	    then
	    #echo '$INCLUDE'" found! Using zone directory: ""$zoneDir"
	    zoneFile=`awk '{print $2}' <<< "$z"`
	    currentZone=`awk '{print $3}' <<< "$z"`
	    currentZone=${currentZone%.*}
	    #echo ${currentZone%.*}
	    processZone $zoneFile
	  fi

	
	  # Setting the $recordType now. We cannot use the column position, as BIND allows
	  # you to exclude certain parts of the record (Hostname, TTL, and IN)

	  # Warning: This has the POTENTIAL to create issues IF the record hostnames contains uppercase
	  # (Which they SHOULDNT, as a best pratice)

	  if [[ $z == *'TXT'* ]] || [[ $z == *'SPF'* ]] || [[ $z == *'MX'* ]] || [[ $z == *'NS'* ]] || [[ $z == *'SRV'* ]] || [[ $z == *'LOC'* ]]
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
	  else

	    # If the record did not contain any of the above it is 99.99% an A record
	    recordType="A"
	  fi


	  # Warning: This is NOT currently working but causes no adverse affect
	  # My hope is to pull in parts of my Generate script in the future.
	  # Reading the GENERATE directive and actually creating the records is a script in and of itself.

	  if [[ $z == *'\$'* ]]
	    then
	    echo '$GENERATE FOUND'
	    currentRecord="$GENERATE"
	  fi


	  # Setting whatever is in the first column to be the "$currentRecord" many times this
	  # will not be an actual record, so we must do some data checking of the variable

	  currentRecord=`awk '{print $1}' <<< "$z"`

	  case $currentRecord in


	    # If the $currentRecord is an ORIGIN directive, we need to change the $currentZone

            '$ORIGIN')
	      if [[ $z == '$ORIGIN '* ]]
		then
		currentZone="${z/\$ORIGIN /}"

	      # Wonky handling of spaces versus tabs (This probably needs cleaned up)
	      elif [[ $z == '$ORIGIN	'* ]]
		then
		currentZone="${z/\$ORIGIN	/}"
	      fi

	      # Ripping any trailing periods off the $currentZone"
	      currentZone=${currentZone%.*};;

	    # If the $currentRecord contains a trailing period, we need to ensure we do
	    # NOT append the $currentZone to the record (as this is a fully-qualified hostname)

	    *'.') 
	      lastFQDN=`echo ${currentRecord%?.*}`
	      printf "${currentRecord%.*}","$recordType\n";;


	    # If the $currentRecord is a TTL, GENERATE, or some other junk, get rid of it
	    # We also get rid of wilcard records here, due to not being able to do a query on *.domain.ksu.edu

            '$TTL'|'$GENERATE'*|'"'*|'4W'|'2h)'|[*]*)
              echo "EXCLUDING: ""$currentRecord" > /dev/null;;


	    # If the $currentRecord is an 'origin' then the $currentRecord is equal
	    # to the $currentZone, so we just print that

            '@')
	      lastFQDN="$currentZone"
	      printf "$currentZone","$recordType\n";;


	    # If the $currentRecord is a record type or a TTL value, that means a hostname
	    # has been excluded which means we use the last know hostname

            'TXT'|'SPF'|'A'|'CNAME'|'DNAME'|'MX'|'NS'|'LOC'|'SRV'|'IN'|[0-9][0-9][0-9]*|'30'|'5m')

	      # Checking to make sure this is not a PTR record, if it is, we dump it for now as reverse is broke

	      if [[ $currentZone == *'in-addr.arpa' ]] || [[ $currentZone == *'IN-ADDR.ARPA' ]]
		then
		echo '' > /dev/null
		else
	      	  printf "$lastFQDN","$recordType\n"
	      fi;;

	    '' )
	      echo "THIS IS A BLANK RECORD, using ""$lastFQDN" > /dev/null;;


	    # For everything else, it's probably a plain jane A record
	    # so print the $currentRecord + the $currentZone

	    *)
	      lastFQDN="$currentRecord"'.'"$currentZone"


	# This is an attempt at dealing with reverse records, it is mostly working except GENERATE directives
	# mess it up (You end up with a reverse record such as 129.130.254.0-255
	# some minor tweaking would fix this, again (Too lazy, and it isn't needed right now)
	#
	# For now, I have it dumping the $currentRecord if the $currentZone is "in-addr.arpa" until this is working

	      if [[ $currentZone == *'in-addr.arpa' ]]
  		then
		echo '' > /dev/null
#  		modRecord="$currentRecord"'.'"$currentZone"
#  		modRecord="${modRecord/.in-addr.arpa/}"
#
#  		OIFS=$IFS
#  		IFS=. read w x y z <<<"$modRecord"
#  		printf "$z"'.'"$y"'.'"$x"'.'"$w\n"
#  		IFS=$OIFS
	      elif [[ $currentZone == *'IN-ADDR.ARPA' ]]
  		then
		echo '' /dev/null
#  		modRecord="$currentRecord"'.'"$currentZone"
#  		modRecord="${modRecord/.IN-ADDR.ARPA/}"
#
#  		OIFS=$IFS
#  		IFS=. read w x y z <<<"$modRecord"
#  		printf "$z"'.'"$y"'.'"$x"'.'"$w\n"
#  		IFS=$OIFS
	      else
 		printf "$currentRecord"'.'"$currentZone","$recordType\n"
	      fi;;

	  esac

	# Unset the $recordType in preparation for the next line
	unset recordType

	fi	     
	fi
      done <<< "$zoneContent"
    # Unset the $currentzone as we are exiting the current zonefile contents
    unset currentZone
}


# Re-write any temp files in-case of a previous partial run
echo '' > /tmp/fqdn-generator.tmp


# Run the createNamed function
createNamed

# Run the processNamed function
processNamed

# Cleanup temp files
rm /tmp/fqdn-generator.tmp
