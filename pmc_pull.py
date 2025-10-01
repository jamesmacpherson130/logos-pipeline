import os, sys, json, time, random, hashlib, datetime, textwrap
from pathlib import Path
import requests
from bs4 import BeautifulSoup
BASE = Path(r"C:\Users\James\OneDrive\Desktop\science")
RAW = BASE/"raw"; PARSED = BASE/"parsed"; JSONL = BASE/"jsonl"/"pmc_catalog.v1.jsonl"; LOG = BASE/"logs"/"pmc_pull.log"
for p in (RAW, PARSED, JSONL.parent, LOG.parent): p.mkdir(parents=True, exist_ok=True)
UA = {"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36"}
SESSION = requests.Session()
def now_utc():
    try:
        return datetime.datetime.now(datetime.UTC)
    except Exception:
        return datetime.datetime.utcnow().replace(tzinfo=datetime.timezone.utc)
def log(msg:str):
    LOG.open("a", encoding="utf-8").write(f"{now_utc().isoformat()} {msg}\n")
def clean(node):
    return "" if node is None else " ".join(node.get_text(separator=" ", strip=True).split())
def meta_first(soup, names):
    for n in names:
        m = soup.find("meta", attrs={"name": n}) or soup.find("meta", attrs={"property": n})
        if m and m.get("content"): return m["content"].strip()
    return ""
def meta_multi(soup, name):
    return [m.get("content","").strip() for m in soup.find_all("meta", attrs={"name": name}) if m.get("content")]
def fetch(url, tries=3):
    last = None
    for _ in range(tries):
        r = SESSION.get(url, headers=UA, timeout=30)
        if r.status_code == 200: return r
        last = r
        log(f"WARN status={r.status_code} url={url}")
        time.sleep(random.uniform(0.8,1.6))
    raise RuntimeError(f"fetch failed ({last.status_code if last else 'no response'})")
def parse(html, url, pmcid):
    soup = BeautifulSoup(html, "lxml")
    title   = meta_first(soup,["citation_title","dc.title"]) or clean(soup.select_one("h1")) or clean(soup.find("title"))
    journal = meta_first(soup,["citation_journal_title","prism.publicationName"])
    date    = meta_first(soup,["citation_publication_date","dc.date","prism.publicationDate"])
    doi     = meta_first(soup,["citation_doi","dc.identifier","prism.doi"])
    authors = meta_multi(soup,"citation_author") or [clean(n) for n in soup.select(".contrib-group .contrib .name") if clean(n)]
    abstract = (clean(soup.select_one("#abstract")) or clean(soup.select_one("section.abstract")) or clean(soup.select_one("div.abstract")))
    body_node = (soup.select_one("article") or soup.select_one("#maincontent") or soup.select_one("#body")
                 or soup.select_one("div#article-content") or soup.select_one("div[itemprop=articleBody]"))
    body_text = clean(body_node)
    return dict(
        pmcid=pmcid, title=title, journal=journal, date=date, doi=doi, authors=authors, url=url,
        abstract=abstract, body_text=body_text, word_count_body=len(body_text.split()),
        fetched_at_utc=now_utc().isoformat(), parser_version="0.2.5"="0.2.4"
    )
def wrap(s, width=120):
    s = (s or "").strip()
    return "\n".join(textwrap.wrap(s, width=width)) if s else ""
def run(ids, wrap_width=120):
    for pmcid in [i.upper().strip() for i in ids if i.strip()]:
        if not pmcid.startswith("PMC"):
            print(f"? skip {pmcid}")
            continue
        url = f"https://pmc.ncbi.nlm.nih.gov/articles/{pmcid}/"
        t0 = time.time()
        try:
            r   = fetch(url)
            rec = parse(r.text, url, pmcid)
            # Save raw HTML
            (RAW/f"{pmcid}.html").write_bytes(r.content)
            # Save wrapped TXT (human-readable)
            parts = [
                f"TITLE: {rec['title']}",
                f"JOURNAL: {rec['journal']}",
                f"DATE: {rec['date']}",
                f"DOI: {rec['doi']}",
                "AUTHORS: " + ", ".join(rec['authors']),
                f"URL: {url}",
                "",
                "ABSTRACT:",
                wrap(rec.get("abstract",""), wrap_width),
                "",
                "BODY:",
                wrap(rec.get("body_text",""), wrap_width)
            ]
            (PARSED/f"{pmcid}.txt").write_text("\n".join(parts), encoding="utf-8")
            # Save JSONL (machine-readable)
            with JSONL.open("a", encoding="utf-8") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            ms = int((time.time()-t0)*1000)
            log(f"OK {pmcid} ms={ms} words={rec['word_count_body']}")
            print(f"? {pmcid} ? {PARSED}\\{pmcid}.txt")
        except Exception as e:
            ms = int((time.time()-t0)*1000)
            log(f"FAIL {pmcid} ms={ms} exc={e}")
            print(f"? {pmcid} ERROR: {e}")
            time.sleep(1.2)
if __name__=="__main__":
    args = sys.argv[1:]
    if not args:
        print("Usage: python pmc_pull.py PMC12345 [PMC...] OR python pmc_pull.py ids.txt")
        sys.exit(1)
    if len(args)==1 and os.path.isfile(args[0]):
        ids = [ln.strip() for ln in open(args[0],encoding="utf-8",errors="ignore") if ln.strip()]
    else:
        ids = args
    run(ids, wrap_width=120)
