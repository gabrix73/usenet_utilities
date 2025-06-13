#!/bin/bash

# Script per stimare le dimensioni del download prima di eseguire pullnews
# Interroga il server NNTP per ottenere statistiche sui gruppi

set -e

# Configurazione
UPSTREAM_SERVER=""
START_DATE="20240101"
LOG_FILE="/tmp/usenet_estimate_$(date +%Y%m%d_%H%M%S).log"
NNTP_TIMEOUT=30

# Dimensioni medie stimate per tipo di gruppo (in KB per articolo)
declare -A AVG_SIZES
AVG_SIZES["alt."]="15"      # Gruppi alt generalmente più grandi
AVG_SIZES["comp."]="8"      # Gruppi comp - tecnici, codice
AVG_SIZES["sci."]="12"      # Gruppi scientifici
AVG_SIZES["soc."]="10"      # Gruppi sociali/culturali
AVG_SIZES["talk."]="8"      # Gruppi di discussione
AVG_SIZES["rec."]="10"      # Gruppi ricreativi
AVG_SIZES["misc."]="9"      # Gruppi vari
AVG_SIZES["news."]="5"      # Gruppi news/admin
AVG_SIZES["uk."]="9"        # Gruppi UK
AVG_SIZES["de."]="10"       # Gruppi tedeschi
AVG_SIZES["it."]="11"       # Gruppi italiani
AVG_SIZES["nl."]="9"        # Gruppi olandesi
AVG_SIZES["fr."]="10"       # Gruppi francesi
AVG_SIZES["free."]="8"      # Gruppi free
AVG_SIZES["relcom."]="12"   # Gruppi relcom
AVG_SIZES["linux."]="8"     # Gruppi Linux
AVG_SIZES["control."]="3"   # Messaggi di controllo
AVG_SIZES["junk"]="6"       # Junk - piccoli
AVG_SIZES["default"]="10"   # Default fallback

# Gruppi da analizzare
NEWSGROUPS=(
    "uk.legal"
    "alt.usage.english"
    "sci.crypt"
    "de.talk.tagesgeschehen"
    "de.test"
    "rec.crafts.metalworking"
    "comp.sys.mac.advocacy"
    "uk.d-i-y"
    "nl.politiek"
    "talk.origins"
    "rec.gambling.poker"
    "sci.physics.relativity"
    "rec.sport.football.college"
    "soc.culture.jewish"
    "alt.society.liberalism"
    "rec.games.pinball"
    "talk.politics.guns"
    "comp.os.linux.advocacy"
    "it.comp.console"
    "sci.physics"
    "relcom.hot-news"
    "misc.jobs.contract"
    "junk"
    "soc.culture.israel"
    "linux.debian.bugs.dist"
    "misc.survivalism"
    "news.lists.filters"
    "soc.men"
    "de.soc.politik.misc"
    "uk.politics.misc"
    "free.usenet"
    "control.cancel"
    "alt.fan.rush-limbaugh"
    "talk.politics.misc"
    "alt.atheism"
    "free.pt"
    "it.politica"
    "rec.sport.pro-wrestling"
    "rec.arts.tv"
    "alt.bestjobsusa.computer.jobs"
    "alt.politics"
    "fr.soc.politique"
    "rec.food.cooking"
    "it.sport.calcio.milan"
    "soc.culture.usa"
    "alt.privacy.anon-server"
    "alt.privacy"
    "alt.cipherpunks"
    "news.software.nntp"
    "news.software.readers"
)

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

show_usage() {
    cat << EOF
Uso: $0 [opzioni]

Opzioni:
    -s SERVER    Server upstream (obbligatorio)
    -d DATE      Data di inizio in formato YYYYMMDD (default: $START_DATE)
    -v           Modalità verbose (mostra dettagli per ogni gruppo)
    -f FORMAT    Formato output: table, csv, json (default: table)
    -h           Mostra questo help

Esempi:
    $0 -s news.example.com
    $0 -s news.example.com -d 20240601 -v
    $0 -s news.example.com -f csv > stima.csv

EOF
}

get_avg_size() {
    local group="$1"
    local size="${AVG_SIZES[default]}"
    
    for prefix in "${!AVG_SIZES[@]}"; do
        if [[ "$group" =~ ^"$prefix" ]]; then
            size="${AVG_SIZES[$prefix]}"
            break
        fi
    done
    
    echo "$size"
}

query_group_stats() {
    local group="$1"
    local server="$2"
    
    # Usa nntpget o telnet per interrogare il server
    local stats=$(timeout $NNTP_TIMEOUT bash -c "
        exec 3<>/dev/tcp/$server/119 2>/dev/null || exit 1
        read -u 3 response
        echo 'GROUP $group' >&3
        read -u 3 group_response
        echo 'QUIT' >&3
        exec 3<&-
        exec 3>&-
        echo \"\$group_response\"
    " 2>/dev/null)
    
    if [[ $stats =~ ^211[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+) ]]; then
        local count="${BASH_REMATCH[1]}"
        local first="${BASH_REMATCH[2]}"
        local last="${BASH_REMATCH[3]}"
        echo "$count:$first:$last"
    else
        echo "0:0:0"
    fi
}

estimate_articles_since_date() {
    local total_articles="$1"
    local first_num="$2"
    local last_num="$3"
    local target_date="$4"
    
    if [ "$total_articles" -eq 0 ] || [ "$first_num" -eq "$last_num" ]; then
        echo "0"
        return
    fi
    
    # Stima approssimativa: assume distribuzione uniforme degli articoli nel tempo
    # Calcola i giorni da gennaio 2024 ad oggi
    local start_timestamp=$(date -d "${target_date:0:4}-${target_date:4:2}-${target_date:6:2}" +%s 2>/dev/null || echo "1704067200")
    local current_timestamp=$(date +%s)
    local days_diff=$(( (current_timestamp - start_timestamp) / 86400 ))
    
    # Stima: suppone che gli articoli siano distribuiti negli ultimi 2 anni
    local total_days=730
    
    # Calcolo semplificato senza bc per evitare problemi con decimali
    local estimated
    if [ "$days_diff" -le 0 ]; then
        estimated=0
    elif [ "$days_diff" -ge "$total_days" ]; then
        estimated="$total_articles"
    else
        # Calcolo percentuale con aritmetica intera
        estimated=$(( (total_articles * days_diff) / total_days ))
    fi
    
    # Assicura che non superi il totale
    if [ "$estimated" -gt "$total_articles" ]; then
        estimated="$total_articles"
    fi
    
    # Minimo 10% degli articoli se il gruppo ha attività
    if [ "$estimated" -lt $(( total_articles / 10 )) ] && [ "$total_articles" -gt 0 ]; then
        estimated=$(( total_articles / 10 ))
    fi
    
    echo "$estimated"
}

format_size() {
    local size_kb="$1"
    
    if [ "$size_kb" -lt 1024 ]; then
        echo "${size_kb} KB"
    elif [ "$size_kb" -lt 1048576 ]; then
        local mb=$(( (size_kb * 10) / 1024 ))
        echo "$((mb / 10)).$((mb % 10)) MB"
    else
        local gb=$(( (size_kb * 10) / 1048576 ))
        echo "$((gb / 10)).$((gb % 10)) GB"
    fi
}

main() {
    local verbose=0
    local format="table"
    
    # Parse argomenti
    while getopts "s:d:vf:h" opt; do
        case $opt in
            s) UPSTREAM_SERVER="$OPTARG" ;;
            d) START_DATE="$OPTARG" ;;
            v) verbose=1 ;;
            f) format="$OPTARG" ;;
            h) show_usage; exit 0 ;;
            \?) echo "Opzione non valida: -$OPTARG" >&2; show_usage; exit 1 ;;
        esac
    done
    
    if [ -z "$UPSTREAM_SERVER" ]; then
        echo "ERRORE: Specificare il server upstream con -s"
        show_usage
        exit 1
    fi
    
    log_message "=== Stima dimensioni download Usenet ==="
    log_message "Server: $UPSTREAM_SERVER"
    log_message "Data inizio: $START_DATE"
    log_message "Gruppi da analizzare: ${#NEWSGROUPS[@]}"
    
    # Verifica connessione server
    if ! timeout 10 bash -c "exec 3<>/dev/tcp/$UPSTREAM_SERVER/119" 2>/dev/null; then
        log_message "ERRORE: Impossibile connettersi a $UPSTREAM_SERVER:119"
        exit 1
    fi
    
    local total_estimated_articles=0
    local total_estimated_size_kb=0
    
    declare -a results
    
    if [ "$format" == "csv" ]; then
        echo "Gruppo,Articoli Totali,Articoli Stimati,Dimensione Stimata KB,Dimensione Stimata"
    elif [ "$format" == "table" ]; then
        printf "%-35s %10s %10s %15s %10s\n" "GRUPPO" "TOT ART" "EST ART" "EST SIZE KB" "EST SIZE"
        printf "%s\n" "$(printf '=%.0s' {1..85})"
    fi
    
    for group in "${NEWSGROUPS[@]}"; do
        log_message "Analizzando: $group"
        
        local stats=$(query_group_stats "$group" "$UPSTREAM_SERVER")
        IFS=':' read -r total_articles first_num last_num <<< "$stats"
        
        local estimated_articles=$(estimate_articles_since_date "$total_articles" "$first_num" "$last_num" "$START_DATE")
        local avg_size_kb=$(get_avg_size "$group")
        local estimated_size_kb=$((estimated_articles * avg_size_kb))
        
        total_estimated_articles=$((total_estimated_articles + estimated_articles))
        total_estimated_size_kb=$((total_estimated_size_kb + estimated_size_kb))
        
        if [ "$format" == "csv" ]; then
            echo "$group,$total_articles,$estimated_articles,$estimated_size_kb,$(format_size $estimated_size_kb)"
        elif [ "$format" == "table" ]; then
            printf "%-35s %10s %10s %15s %10s\n" \
                "$group" "$total_articles" "$estimated_articles" "$estimated_size_kb" "$(format_size $estimated_size_kb)"
        fi
        
        if [ "$verbose" -eq 1 ]; then
            log_message "  Totali: $total_articles, Stimati: $estimated_articles, Dimensione: $(format_size $estimated_size_kb)"
        fi
        
        sleep 1  # Pausa per non sovraccaricare il server
    done
    
    if [ "$format" == "table" ]; then
        printf "%s\n" "$(printf '=%.0s' {1..85})"
        printf "%-35s %10s %10s %15s %10s\n" \
            "TOTALE" "" "$total_estimated_articles" "$total_estimated_size_kb" "$(format_size $total_estimated_size_kb)"
    elif [ "$format" == "csv" ]; then
        echo "TOTALE,,$total_estimated_articles,$total_estimated_size_kb,$(format_size $total_estimated_size_kb)"
    fi
    
    log_message "=== Riassunto Stima ==="
    log_message "Articoli stimati totali: $total_estimated_articles"
    log_message "Dimensione stimata totale: $(format_size $total_estimated_size_kb)"
    log_message "Log salvato in: $LOG_FILE"
    
    # Avvertenze
    echo ""
    echo "NOTA: Questa è una stima approssimativa basata su:"
    echo "- Distribuzione temporale degli articoli (può variare molto)"
    echo "- Dimensioni medie per categoria di gruppo"
    echo "- Disponibilità effettiva degli articoli sul server"
    echo "- La dimensione reale può variare significativamente"
}

# Verifica dipendenze
if ! command -v timeout >/dev/null 2>&1; then
    echo "ERRORE: 'timeout' non trovato. Installare con: sudo apt-get install coreutils"
    exit 1
fi

main "$@"
