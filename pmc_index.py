import glob, re, os, csv
def grab(label, text):
    m=re.search(rf'{label}:\s*(.*)$', text, flags=re.M)
    return m.group(1).strip() if m else ''
rows=[]
for path in glob.glob(r'C:\Users\James\OneDrive\Desktop\science\parsed\PMC*.txt'):
    t=open(path,encoding='utf-8',errors='ignore').read()
    pmcid=os.path.basename(path)[:-4]
    title=grab('TITLE',t)
    journal=grab('JOURNAL',t)
    date=grab('DATE',t)
    doi=grab('DOI',t)
    url=grab('URL',t)
    rows.append([pmcid,title,journal,date,doi,url])
with open(r'C:\Users\James\OneDrive\Desktop\science\science_index.csv','w',newline='',encoding='utf-8') as f:
    csv.writer(f).writerows([['PMCID','TITLE','JOURNAL','DATE','DOI','URL'],*rows])
