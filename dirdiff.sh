#!/usr/bin/env bash
#-----------------------------------------------------------#
# @author: dep
# @link: https://github.com/demmonico
# @package: https://github.com/demmonico/bash
#
# This script comparing content of 2 folders recursively
#
# Format: ./diff.sh [OPTIONS] [--filter bfsmd] FOLDER_1 FOLDER_2
#   OPTIONS:
#       -d|--duplicates - flag whether show detailed info about duplicates
#   PARAMETERS:
#       -f|--filter - filter output groups (b - both equal, f - first exists, s - second exists, m - modified)
#-----------------------------------------------------------#

start=`date +%s`



function getFullPath() {
    # prepare
    local DIR=$1;
    if [[ "${DIR}" != /* ]]; then DIR="${ROOT_DIR}/${DIR}"; fi
    echo ${DIR}
}

function buildFileList() {

    # prepare
    local ORDER=$1
    local DIR="$(getFullPath $2)"

    # get files
    local FILES;
    readarray FILES < <(find "${DIR}" -type f -exec bash -c "stat --printf='%n<|>%y<|>%s<|>' '{}' \
        && (basename '{}' | xargs echo -n) && echo -n '<|>' \
        && (md5sum '{}' | awk '{printf(\$1)}') \
        && echo '<<||>>' " \; | sort -k 1);

    # parse files
    for i in "${FILES[@]}"
    do
        local FILEPATH=$( echo "$i" | awk -F'<|>' '{print $1}' )
        local FILESUBPATH="${FILEPATH#${DIR}/}"
        eval LIST${ORDER}\[\"\$\{FILESUBPATH\}\"\]=\"\$i\"
    done
}

function filterOutputList() {

    local DECISION=$1;

    local FILTER_BOTH='' && [[ "${DECISION}" == '1==2' ]] && [[ "${OUTPUT_GROUPS}" =~ [b] ]] && echo 'FILTER_BOTH' && return;
    local FILTER_MODIFIED='' && [[ "${DECISION}" == '1<>2'* ]] && [[ "${OUTPUT_GROUPS}" =~ [m] ]] && echo 'FILTER_MODIFIED' && return;
    local FILTER_FIRST='' && [[ "${DECISION}" == '1->2' ]] && [[ "${OUTPUT_GROUPS}" =~ [f] ]] && echo 'FILTER_FIRST' && return;
    local FILTER_SECOND='' && [[ "${DECISION}" == '1<-2' ]] && [[ "${OUTPUT_GROUPS}" =~ [s] ]] && echo 'FILTER_SECOND' && return;

    local FILTER_DUPLICATES='' && [[ "${DECISION}" == 'duplicates' ]] && [[ "${OUTPUT_GROUPS}" =~ [d] ]] && echo 'FILTER_DUPLICATES' && return;
}

function buildOutputTable() {
    
    local FILE=$1;
    # parse flags
    case "$2" in
    '1->2')
        BEGIN="${RED}[1][->][_]${NC}"
        shift ;;
    '1==2')
        BEGIN="${GREEN}[1][==][2]${NC}"
        shift ;;
    '1<>2'*)
        local TYPE;
        #if [ "${2##*-}" == 'h' ]; then TYPE=' [hash]'; fi
        #BEGIN="${YELLOW}[1][<>][2]${TYPE}${NC}"
        BEGIN="${YELLOW}[1][<>][2]${NC}"
        shift ;;
    '1<-2')
        BEGIN="${RED}[_][<-][2]${NC}"
        shift ;;
    *)
        echo "Invalid decision value '$2'"
        exit
        ;;
    esac
    # add doubles info
    MSG_DOUBLE=''
    if [ ! -z "${DUPLICATES["${FILE}"]}" ]; then
        MSG_DOUBLE="\n  ${BLUE}[double] ${HASHES["${DUPLICATES["${FILE}"]}"]}${NC}"
    elif [ ! -z "${ORIGINS["${FILE}"]}" ]; then
        MSG_DOUBLE="\n  ${BLUE}[double] ${ORIGINS["${FILE}"]}${NC}"
    fi

    #REASON=${REASONS["${FILE}"]:+" (${REASONS["${FILE}"]})"}
    REASON=${REASONS["${FILE}"]:+" ${REASONS["${FILE}"]}"}
    echo -e "${BEGIN} ${FILE}${REASON}${MSG_DOUBLE}"
}

#-----------------------------------------------------------#



# set colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# get params
OUTPUT_GROUPS='bfsmd'
isShowDuplicatesDetailed=''
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        -d|--duplicates)
            isShowDuplicatesDetailed='true'
            ;;
        -f|--filter)
            # validate
            if [ -z "$2" ] || [[ ! $2 =~ ^[bfsmd]*$ ]]; then
                echo -e "${RED}Error:${NC} please specify filter value (should match pattern [bfsmd])"
                exit
            else
                OUTPUT_GROUPS="$2"
                shift
            fi
            ;;
        *)
            # validate
            if [[ $1 == -* ]]; then
                echo -e "${RED}Error:${NC} it seems that using unknown option"
                exit
            elif [ -z "$1" ] || [ -z "$2" ]; then
                echo -e "${RED}Error:${NC} please specify 2 directories"
                exit
            else
                DIR1="$(getFullPath $1)"
                DIR2="$(getFullPath $2)"
                shift
            fi
            ;;
    esac
        shift
done

#-----------------------------------------------------------#



# build files lists
declare -A LIST1
declare -A LIST2
echo -n -e "\r\e[0KBuilding files list 1 ..."
buildFileList 1 ${DIR1};
echo -n -e "\r\e[0KBuilding files list 2 ..."
buildFileList 2 ${DIR2};



# comparing
echo -n -e "\r\e[0KComparing files lists ..."
# array of decisions
declare -A FLAGS
# reasons for modified files
declare -A REASONS
# hashes array for search duplicates
declare -A HASHES
declare -A DUPLICATES
declare -A ORIGINS
# list of filenames for sorting
FILENAMES=()

# process LIST1
for FILE in "${!LIST1[@]}"
do
    LINE1="${LIST1[${FILE}]}"
    LINE2="${LIST2[${FILE}]}"

    HASH1="$( echo "${LINE1}" | awk -F'<|>' '{print $9}' )"
    # collect hash for filter duplicates in list 1
    if [ ! -z "$(filterOutputList "duplicates")" ]; then
        if [ -z "${HASHES["${HASH1}"]}" ]; then
            HASHES["${HASH1}"]="${FILE}"
        # collect duplicates
        else
            # collect double
            DUPLICATES["${FILE}"]="${HASH1}"
            # collect origin
            ORIGINS["${HASHES["${HASH1}"]}"]="${FILE}"
        fi
    fi

    # 1 -> 2
    if [ -z "${LINE2}" ]; then
        DECISION='1->2'

    # equivalent names
    else
        HASH2="$( echo "${LINE2}" | awk -F'<|>' '{print $9}' )"

        MTIME1=$( echo "${LINE1}" | awk -F'<|>' '{print $3}' )
        MTIME2=$( echo "${LINE2}" | awk -F'<|>' '{print $3}' )

        # the different files (via MD5) having the same names
        if [ "${HASH1}" != "${HASH2}" ]; then
            DECISION='1<>2-h'
            # add to REASONS
            REASONS["${FILE}"]="${YELLOW}[hash]${NC} ${HASH1} vs ${HASH2}"

        # the same files having the different modify time
        elif [ "${MTIME1}" != "${MTIME2}" ]; then
            DECISION='1<>2-m'
            # add to REASONS
            MTIME1="$( date --date="${MTIME1}" "+%Y:%m:%d %H:%M:%S" )"
            MTIME2="$( date --date="${MTIME2}" "+%Y:%m:%d %H:%M:%S" )"
            REASONS["${FILE}"]="${YELLOW}[mtime]${NC} ${MTIME1} vs ${MTIME2}"

        # the same files
        else
            DECISION='1==2'
        fi

        # collect hash for filter duplicates list 2 -> list 1
        if [ ! -z "$(filterOutputList "duplicates")" ]; then
            if [ -z "${HASHES["${HASH2}"]}" ]; then
                HASHES["${HASH2}"]="${FILE}"
            # collect duplicates
            elif [ "${HASH1}" != "${HASH2}" ]; then
                # collect double
                DUPLICATES["${FILE}"]="${HASH2}"
                # collect origin
                ORIGINS["${HASHES["${HASH2}"]}"]="${FILE}"
            fi
        fi

        # remove from LIST2
        unset LIST2["${FILE}"]
    fi

    # filter items for output
    if [ ! -z "$(filterOutputList "${DECISION}")" ]; then
        FLAGS["${FILE}"]="${DECISION}"
        FILENAMES+=("${FILE}")
    fi

done

# process LIST2
# 1 <- 2
for FILE in "${!LIST2[@]}"
do
    # filter items for output
    DECISION='1<-2'
    if [ ! -z "$(filterOutputList "${DECISION}")" ]; then
        FLAGS["${FILE}"]="${DECISION}"
        FILENAMES+=("${FILE}")
    fi

    HASH2="$( echo "${LIST2[${FILE}]}" | awk -F'<|>' '{print $9}' )"
    # collect hash for filter duplicates in list 2
    if [ ! -z "$(filterOutputList "duplicates")" ]; then
        if [ -z "${HASHES["${HASH2}"]}" ]; then
            HASHES["${HASH2}"]="${FILE}"
        # collect duplicates
        else
            # collect double
            DUPLICATES["${FILE}"]="${HASH2}"
            # collect origin
            ORIGINS["${HASHES["${HASH2}"]}"]="${FILE}"
        fi
    fi
done



# sort results
echo -n -e "\r\e[0KSorting results ..."
IFS=$'\n' FILENAMES=($(sort <<<"${FILENAMES[*]}"))
unset IFS



# print output table
echo -e "\r\e[0KLegend: '1==2' - both equal, '1<>2' - modified, '1->_'/'_<-2' - exists at the '1'/'2' dir only."
echo "Compare results (output filter '${OUTPUT_GROUPS}' was applied):"
echo '---------------------------------------------------'
for FILE in "${FILENAMES[@]}"
do
    echo "$(buildOutputTable "${FILE}" "${FLAGS["${FILE}"]}")"
done

# print duplicates
if [ ! -z "$(filterOutputList "duplicates")" ]  && [ ! -z "${isShowDuplicatesDetailed}" ]; then
    echo ''
    echo "Duplicates:"
    echo '-----------'
    for FILE in "${!DUPLICATES[@]}"
    do
        HASH="${DUPLICATES["${FILE}"]}"
        echo -e "${YELLOW}[hash]${NC} ${HASH}"
        echo -e "${YELLOW}[1]${NC} ${HASHES["${HASH}"]}"

        # TODO add search for several duplicates for showing them into single block
        echo -e "${YELLOW}[2]${NC} ${FILE}"
        echo ''
    done
fi

echo "Runtime: $(($(date +%s)-$start)) sec"


# TODO syncing
