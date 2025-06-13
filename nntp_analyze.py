#!/usr/bin/env python3
"""
NNTP Server Analyzer - Trova i 50 newsgroup più attivi
Analizza qualsiasi server NNTP per identificare i gruppi con più traffico
"""

import nntplib
import sys
import argparse
from datetime import datetime, timedelta
import re
import time
from collections import namedtuple

# Struttura dati per gruppo
GroupInfo = namedtuple('GroupInfo', ['name', 'count', 'low', 'high', 'flag', 'activity_score', 'posts_per_day'])

class NNTPAnalyzer:
    def __init__(self, server, port=119, username=None, password=None, timeout=30):
        self.server = server
        self.port = port
        self.username = username
        self.password = password
        self.timeout = timeout
        self.connection = None
        
    def connect(self):
        """Connetti al server NNTP"""
        try:
            print(f"🔌 Connessione a {self.server}:{self.port}...")
            self.connection = nntplib.NNTP(self.server, port=self.port, timeout=self.timeout)
            
            # Autenticazione se richiesta
            if self.username and self.password:
                self.connection.login(self.username, self.password)
                print(f"✅ Autenticato come {self.username}")
            
            # Info server
            welcome = self.connection.getwelcome()
            print(f"📡 Server: {welcome}")
            return True
            
        except Exception as e:
            print(f"❌ Errore connessione: {e}")
            return False
    
    def disconnect(self):
        """Disconnetti dal server"""
        if self.connection:
            try:
                self.connection.quit()
                print("🔚 Disconnesso dal server")
            except:
                pass
    
    def debug_group_data(self, groups_data, max_show=3):
        """Debug: mostra struttura dati gruppi"""
        print(f"\n🔍 DEBUG: Analisi struttura dati ({len(groups_data)} gruppi)")
        print("-" * 60)
        
        for i, group_data in enumerate(groups_data[:max_show]):
            print(f"Gruppo {i+1}:")
            print(f"  Tipo: {type(group_data)}")
            
            if hasattr(group_data, 'group'):
                print(f"  Nome: {group_data.group}")
                print(f"  First: {group_data.first}")
                print(f"  Last: {group_data.last}")
                print(f"  Flag: {group_data.flag}")
            elif isinstance(group_data, (bytes, str)):
                content = group_data.decode() if isinstance(group_data, bytes) else group_data
                print(f"  Contenuto: {content[:80]}...")
            else:
                print(f"  Contenuto: {str(group_data)[:80]}...")
            print()
        
        if len(groups_data) > max_show:
            print(f"... e altri {len(groups_data) - max_show} gruppi")
        print("-" * 60)

    def get_active_groups(self, pattern=None, limit=None):
        """Ottieni lista gruppi attivi con statistiche"""
        try:
            print("📋 Recupero lista gruppi attivi...")
            
            # Ottieni lista completa
            resp, groups_data = self.connection.list()
            total_groups = len(groups_data)
            print(f"📊 Trovati {total_groups} gruppi totali")
            
            # Debug prima dei filtri
            if total_groups > 0:
                self.debug_group_data(groups_data, 3)
            
            # Filtra per pattern se specificato
            if pattern:
                pattern_re = re.compile(pattern, re.IGNORECASE)
                if hasattr(groups_data[0], 'group'):
                    # Oggetti GroupInfo
                    groups_data = [g for g in groups_data if pattern_re.search(g.group)]
                else:
                    # Bytes/string
                    groups_data = [g for g in groups_data if pattern_re.search(
                        g.decode() if isinstance(g, bytes) else str(g)
                    )]
                print(f"🔍 Filtrati a {len(groups_data)} gruppi (pattern: {pattern})")
            
            # Limita numero se specificato
            if limit and len(groups_data) > limit:
                groups_data = groups_data[:limit]
                print(f"✂️ Limitati a {limit} gruppi per analisi veloce")
            
            return groups_data
            
        except Exception as e:
            print(f"❌ Errore recupero gruppi: {e}")
            import traceback
            traceback.print_exc()
            return []
    
    def analyze_group_activity(self, group_data):
        """Analizza attività di un singolo gruppo"""
        try:
            # group_data può essere bytes o oggetto GroupInfo
            if hasattr(group_data, 'group'):
                # È già un oggetto GroupInfo da nntplib
                name = group_data.group
                high = int(group_data.last)
                low = int(group_data.first)
                flag = group_data.flag
            else:
                # È bytes raw, parse manualmente
                if isinstance(group_data, bytes):
                    line = group_data.decode()
                else:
                    line = str(group_data)
                    
                parts = line.split()
                if len(parts) < 4:
                    return None
                    
                name = parts[0]
                high = int(parts[1])
                low = int(parts[2])
                flag = parts[3]
            
            # Calcola metriche attività
            total_articles = max(0, high - low + 1) if high >= low else 0
            
            # Skip gruppi vuoti o con problemi
            if total_articles <= 0 or high <= 0:
                return None
            
            # Stima posts per giorno (approssimata)
            # Assumiamo che i gruppi più recenti abbiano numerazione più alta
            days_estimate = max(1, total_articles / 10)  # Stima conservativa
            posts_per_day = total_articles / days_estimate
            
            # Score attività: combina volume totale e intensità
            activity_score = total_articles * 0.7 + posts_per_day * 0.3
            
            return GroupInfo(
                name=name,
                count=total_articles,
                low=low,
                high=high,
                flag=flag,
                activity_score=activity_score,
                posts_per_day=posts_per_day
            )
            
        except (ValueError, IndexError, AttributeError) as e:
            # Errori di parsing dati
            return None
        except Exception as e:
            print(f"⚠️ Errore inaspettato analisi gruppo: {e}")
            return None
    
    def analyze_server(self, pattern=None, quick_scan=False):
        """Analizza server completo"""
        if not self.connect():
            return []
        
        try:
            # Limita gruppi per scan veloce
            limit = 1000 if quick_scan else None
            groups_data = self.get_active_groups(pattern, limit)
            
            if not groups_data:
                print("❌ Nessun gruppo trovato")
                return []
            
            print(f"⚡ Analisi attività in corso...")
            analyzed_groups = []
            failed_count = 0
            
            for i, group_data in enumerate(groups_data):
                # Progress indicator
                if i % 100 == 0:
                    progress = (i / len(groups_data)) * 100
                    print(f"📈 Progresso: {progress:.1f}% ({i}/{len(groups_data)})")
                
                group_info = self.analyze_group_activity(group_data)
                if group_info and group_info.count > 0:
                    analyzed_groups.append(group_info)
                elif group_info is None:
                    failed_count += 1
                    if failed_count <= 5:  # Mostra solo primi 5 errori
                        print(f"⚠️ Skip gruppo invalido: {group_data}")
            
            # Ordina per attività (score decrescente)
            analyzed_groups.sort(key=lambda g: g.activity_score, reverse=True)
            
            print(f"✅ Analisi completata: {len(analyzed_groups)} gruppi validi")
            if failed_count > 0:
                print(f"⚠️ Gruppi skippati: {failed_count}")
            return analyzed_groups
            
        finally:
            self.disconnect()
    
    def print_top_groups(self, groups, top_n):
        """Stampa i top N gruppi più attivi"""
        if not groups:
            print("❌ Nessun gruppo da mostrare")
            return
        
        print(f"\n🔍 DEBUG PRINT: Parametro ricevuto top_n = {top_n}")
        print(f"🔍 DEBUG PRINT: Gruppi disponibili = {len(groups)}")
        
        actual_top = min(top_n, len(groups))
        
        print(f"\n🏆 TOP {actual_top} NEWSGROUPS PIÙ ATTIVI")
        print("=" * 100)
        print(f"{'#':<4} {'NEWSGROUP':<40} {'ARTICOLI':<10} {'RANGE':<15} {'POST/DAY':<10} {'SCORE':<8}")
        print("-" * 100)
        
        # STAMPA ESATTAMENTE top_n GRUPPI (non hardcoded!)
        groups_to_show = groups[:top_n]
        for i, group in enumerate(groups_to_show, 1):
            range_str = f"{group.low}-{group.high}"
            print(f"{i:<4} {group.name:<40} {group.count:<10} {range_str:<15} {group.posts_per_day:<10.1f} {group.activity_score:<8.0f}")
        
        print("-" * 100)
        print(f"📊 Server: {self.server}")
        print(f"📅 Analisi: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"💡 Mostrati {len(groups_to_show)} gruppi su {len(groups)} totali analizzati")
    
    def export_results(self, groups, filename=None, top_n=50):
        """Esporta risultati in file"""
        if not filename:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            filename = f"nntp_analysis_{self.server}_{timestamp}.txt"
        
        try:
            with open(filename, 'w') as f:
                f.write(f"NNTP Server Analysis: {self.server}:{self.port}\n")
                f.write(f"Analysis Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write(f"Total Groups Analyzed: {len(groups)}\n")
                f.write("=" * 80 + "\n\n")
                
                f.write(f"TOP {min(top_n, len(groups))} MOST ACTIVE NEWSGROUPS:\n")
                f.write("-" * 80 + "\n")
                
                for i, group in enumerate(groups[:top_n], 1):
                    f.write(f"{i:3d}. {group.name}\n")
                    f.write(f"     Articles: {group.count} (range: {group.low}-{group.high})\n")
                    f.write(f"     Est. Posts/Day: {group.posts_per_day:.1f}\n")
                    f.write(f"     Activity Score: {group.activity_score:.0f}\n\n")
                
                # Lista solo nomi per pullnews - divisa in blocchi se troppo lunga
                f.write("\nGROUP NAMES FOR PULLNEWS:\n")
                f.write("-" * 40 + "\n")
                group_names = [g.name for g in groups[:top_n]]
                
                # Se troppi gruppi, dividi in blocchi da 15
                if len(group_names) > 25:
                    f.write("# Comando completo (tutti i gruppi):\n")
                    f.write(",".join(group_names) + "\n\n")
                    
                    f.write("# Comandi divisi in blocchi (per evitare linee troppo lunghe):\n")
                    for i in range(0, len(group_names), 15):
                        chunk = group_names[i:i+15]
                        f.write(f"# Blocco {i//15 + 1}:\n")
                        f.write(",".join(chunk) + "\n\n")
                else:
                    f.write(",".join(group_names) + "\n")
            
            print(f"💾 Risultati salvati in: {filename}")
            return filename
            
        except Exception as e:
            print(f"❌ Errore salvataggio: {e}")
            return None

def main():
    parser = argparse.ArgumentParser(description='Analizza server NNTP per trovare newsgroup più attivi')
    parser.add_argument('server', help='Server NNTP da analizzare')
    parser.add_argument('-p', '--port', type=int, default=119, help='Porta server (default: 119)')
    parser.add_argument('-u', '--username', help='Username per autenticazione')
    parser.add_argument('-w', '--password', help='Password per autenticazione')
    parser.add_argument('-n', '--top', type=int, default=50, help='Numero top gruppi da mostrare (default: 50)')
    parser.add_argument('-f', '--filter', help='Pattern regex per filtrare gruppi (es: "alt.*")')
    parser.add_argument('-q', '--quick', action='store_true', help='Scan veloce (primi 1000 gruppi)')
    parser.add_argument('-o', '--output', help='File output per salvare risultati')
    parser.add_argument('-t', '--timeout', type=int, default=30, help='Timeout connessione (default: 30s)')
    parser.add_argument('-d', '--debug', action='store_true', help='Modalità debug con output dettagliato')
    
    args = parser.parse_args()
    
    print("🔍 NNTP SERVER ANALYZER - TOP 50")
    print("=" * 50)
    print(f"🎯 RICHIESTI: {args.top} gruppi più attivi")
    print(f"📋 DEBUG: Parametro args.top = {args.top}")
    
    # Crea analyzer
    analyzer = NNTPAnalyzer(
        server=args.server,
        port=args.port,
        username=args.username,
        password=args.password,
        timeout=args.timeout
    )
    
    # Esegui analisi
    start_time = time.time()
    groups = analyzer.analyze_server(pattern=args.filter, quick_scan=args.quick)
    analysis_time = time.time() - start_time
    
    if groups:
        print(f"✅ Analisi completata: {len(groups)} gruppi validi")
        print(f"🎯 Preparazione output per top {args.top} gruppi...")
        
        # Mostra risultati - PASSA ESPLICITAMENTE IL PARAMETRO
        analyzer.print_top_groups(groups, args.top)
        
        # Salva se richiesto
        if args.output:
            analyzer.export_results(groups, args.output, args.top)
        
        print(f"\n⏱️ Tempo analisi: {analysis_time:.1f} secondi")
        
        # Suggerimenti pullnews - gestisce liste lunghe
        top_groups = groups[:args.top]
        print(f"\n📊 TOTALE GRUPPI ANALIZZATI: {len(groups)}")
        print(f"🎯 TOP GRUPPI MOSTRATI: {len(top_groups)}")
        
        if len(top_groups) <= 25:
            # Lista corta - comando singolo
            group_list = ",".join([g.name for g in top_groups])
            print(f"\n🚀 COMANDO PULLNEWS SUGGERITO:")
            print(f"pullnews -h {args.server} -g \"{group_list}\" -d 30")
        else:
            # Lista lunga - suggerisci blocchi
            print(f"\n🚀 SUGGERIMENTI PULLNEWS (per {len(top_groups)} gruppi):")
            print("📋 Opzione 1 - Importa tutto (può essere lento):")
            group_list = ",".join([g.name for g in top_groups])
            print(f"pullnews -h {args.server} -g \"{group_list[:200]}...\" -d 30")
            
            print("\n📋 Opzione 2 - Importa a blocchi (raccomandato):")
            for i in range(0, min(45, len(top_groups)), 15):  # Primi 45 divisi in blocchi da 15
                chunk = top_groups[i:i+15]
                chunk_names = ",".join([g.name for g in chunk])
                print(f"# Blocco {i//15 + 1} (top {i+1}-{i+len(chunk)}):")
                print(f"pullnews -h {args.server} -g \"{chunk_names}\" -d 30")
            
            print(f"\n📊 Usa -o file.txt per salvare la lista completa!")
        
    else:
        print("❌ Analisi fallita o nessun gruppo trovato")
        
        if args.debug:
            print("\n🔧 DEBUG INFO:")
            print("- Controlla che il server NNTP sia raggiungibile")
            print("- Verifica che il server abbia gruppi attivi")  
            print("- Prova con --quick per limitare l'analisi")
            print("- Usa --filter per cercare gruppi specifici")
        
        sys.exit(1)

if __name__ == "__main__":
    main()
