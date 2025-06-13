#!/bin/bash

# Script per scaricare articoli Usenet dal gennaio 2024 con pullnews
# Da eseguire come utente 'news' su server INN2 Ubuntu 22.04
# Posizionare in /usr/lib/news/bin/ o altra directory appropriata

set -e

# Configurazione
PULLNEWS_BIN="/usr/lib/news/bin/pullnews"
LOG_DIR="/var/log/news"
LOG_FILE="$LOG_DIR/pullnews_backfill_$(date +%Y%m%d_%H%M%S).log"
START_DATE="20240101"  # Data di inizio: 1 gennaio 2024
UPSTREAM_SERVER=""     # Inserire qui il server upstream (es. news.example.com)
MAX_ARTICLES=1000      # Numero massimo di articoli per gruppo per sessione

# Elenco dei gruppi di discussione
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

# Funzioni
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_prerequisites() {
    log_message "Verifica prerequisiti..."
    
    # Verifica utente
    if [ "$(whoami)" != "news" ]; then
        log_message "ERRORE: Questo script deve essere eseguito dall'utente 'news'"
        exit 1
    fi
    
    # Verifica pullnews
    if [ ! -x "$PULLNEWS_BIN" ]; then
        log_message "ERRORE: pullnews non trovato in $PULLNEWS_BIN"
        exit 1
    fi
    
    # Verifica directory log
    if [ ! -d "$LOG_DIR" ]; then
        log_message "Creazione directory log: $LOG_DIR"
        mkdir -p "$LOG_DIR"
    fi
    
    # Verifica server upstream
    if [ -z "$UPSTREAM_SERVER" ]; then
        log_message "ERRORE: Specificare il server upstream nella variabile UPSTREAM_SERVER"
        exit 1
    fi
}

pull_newsgroup() {
    local group="$1"
    local retry_count=0
    local max_retries=3
    
    log_message "Inizio download per gruppo: $group"
    
    while [ $retry_count -lt $max_retries ]; do
        if $PULLNEWS_BIN -h "$UPSTREAM_SERVER" -g "$group" -s "$START_DATE" -n "$MAX_ARTICLES" >> "$LOG_FILE" 2>&1; then
            log_message "Completato con successo: $group"
            return 0
        else
            retry_count=$((retry_count + 1))
            log_message "Errore nel gruppo $group, tentativo $retry_count/$max_retries"
            sleep 5
        fi
    done
    
    log_message "ERRORE: Fallimento definitivo per gruppo $group dopo $max_retries tentativi"
    return 1
}

show_usage() {
    cat << EOF
Uso: $0 [opzioni]

Opzioni:
    -s SERVER    Server upstream (obbligatorio se non impostato nello script)
    -d DATE      Data di inizio in formato YYYYMMDD (default: $START_DATE)
    -n NUM       Numero massimo articoli per gruppo (default: $MAX_ARTICLES)
    -g GROUP     Scarica solo un gruppo specifico
    -l           Lista i gruppi configurati
    -h           Mostra questo help

Esempi:
    $0 -s news.example.com
    $0 -s news.example.com -d 20240601 -n 500
    $0 -g "sci.physics" -s news.example.com

EOF
}

list_groups() {
    log_message "Gruppi configurati:"
    for group in "${NEWSGROUPS[@]}"; do
        echo "  - $group"
    done
}

# Parsing argomenti
while getopts "s:d:n:g:lh" opt; do
    case $opt in
        s)
            UPSTREAM_SERVER="$OPTARG"
            ;;
        d)
            START_DATE="$OPTARG"
            ;;
        n)
            MAX_ARTICLES="$OPTARG"
            ;;
        g)
            SINGLE_GROUP="$OPTARG"
            ;;
        l)
            list_groups
            exit 0
            ;;
        h)
            show_usage
            exit 0
            ;;
        \?)
            echo "Opzione non valida: -$OPTARG" >&2
            show_usage
            exit 1
            ;;
    esac
done

# Main
main() {
    log_message "=== Inizio script pullnews backfill ==="
    log_message "Server upstream: $UPSTREAM_SERVER"
    log_message "Data di inizio: $START_DATE"
    log_message "Max articoli per gruppo: $MAX_ARTICLES"
    
    check_prerequisites
    
    local failed_groups=()
    local successful_groups=()
    local total_groups=0
    
    if [ -n "$SINGLE_GROUP" ]; then
        log_message "Modalità gruppo singolo: $SINGLE_GROUP"
        if pull_newsgroup "$SINGLE_GROUP"; then
            successful_groups+=("$SINGLE_GROUP")
        else
            failed_groups+=("$SINGLE_GROUP")
        fi
        total_groups=1
    else
        total_groups=${#NEWSGROUPS[@]}
        log_message "Inizio download di $total_groups gruppi..."
        
        for group in "${NEWSGROUPS[@]}"; do
            if pull_newsgroup "$group"; then
                successful_groups+=("$group")
            else
                failed_groups+=("$group")
            fi
            
            # Pausa tra i gruppi per non sovraccaricare il server
            sleep 2
        done
    fi
    
    # Statistiche finali
    log_message "=== Statistiche finali ==="
    log_message "Gruppi processati: $total_groups"
    log_message "Successi: ${#successful_groups[@]}"
    log_message "Fallimenti: ${#failed_groups[@]}"
    
    if [ ${#failed_groups[@]} -gt 0 ]; then
        log_message "Gruppi falliti:"
        for group in "${failed_groups[@]}"; do
            log_message "  - $group"
        done
    fi
    
    log_message "Log completo salvato in: $LOG_FILE"
    log_message "=== Fine script ==="
}

# Esecuzione
main "$@"
