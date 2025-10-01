import argparse, textwrap, glob, os, sys
def wrap_text_block(s, width):
    if not s: return s
    return "\n".join(textwrap.wrap(s.strip(), width=width))
def process_one(path, width, inplace):
    txt = open(path, encoding="utf-8", errors="ignore").read()
    try:
        a_tag = "\nABSTRACT:\n"
        b_tag = "\n\nBODY:\n"
        iA = txt.index(a_tag)
        iB = txt.index(b_tag)
    except ValueError:
        # Not a standard layout; skip
        return False
    head = txt[:iA+len(a_tag)]
    abstract = txt[iA+len(a_tag):iB].strip()
    body = txt[iB+len(b_tag):].strip()
    abstract_wr = wrap_text_block(abstract, width)
    body_wr = wrap_text_block(body, width)
    new_txt = head + abstract_wr + "\n" + b_tag.lstrip("\n") + body_wr + "\n"
    if inplace:
        open(path, "w", encoding="utf-8").write(new_txt)
    else:
        out = path.replace(".txt", ".wrapped.txt")
        open(out, "w", encoding="utf-8").write(new_txt)
    return True
if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, help="science root folder")
    ap.add_argument("--width", type=int, default=120)
    ap.add_argument("--inplace", action="store_true")
    args = ap.parse_args()
    parsed_dir = os.path.join(args.root, "parsed")
    count = 0
    for path in glob.glob(os.path.join(parsed_dir, "PMC*.txt")):
        if process_one(path, args.width, args.inplace): count += 1
    print(f"Wrapped {count} files at width={args.width}. Inplace={args.inplace}")
