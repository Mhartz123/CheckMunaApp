"""Convert the cleaned FDA Philippines drug-advisory CSV into the JSON asset
the app matches scanned product names against.

    python scripts/convert_fda_dataset.py [path/to/FDA_Drug_Advisories_Cleaned.csv]

The CSV has three columns: Product Name, Advisory Number, Date Posted.

Output is an array of
    [name, advisory_number, category, date_posted, keys, anchors]
tuples (array-of-arrays, to avoid repeating key names thousands of times).

`keys` and `anchors` are the false-flag gate, computed here once rather than
on the phone:

- keys: the entry's *distinctive* words. Dosage forms ("tablets", "pian"),
  generic drug names ("paracetamol", "…mycin"), label boilerplate ("as
  reflected in the package insert"), strengths/sizes, and words shared by
  many entries ("otc", "herbal") are removed. What is left is what actually
  names the product.
- anchors: the keys that are not ordinary words — at least 5 letters and not a
  whole-word token in the bundled BERT vocabulary (assets/tokenizer/vocab.json,
  ~30k common English words and names). "efficascent" is an anchor; "premium",
  "tiger", "cough" are not.

An entry is only written out if it has at least MIN_KEYS keys totalling
MIN_KEY_CHARS letters, and at least one anchor. Everything else — "Tetracycline
Tablets", "Alcohol 70% Solution 1L", "Snow King Medicated Oil" — is a name
that legitimate products share, and matching it could only produce a false
Warning, so it is dropped.

Re-run this whenever the CSV is updated with new FDA advisories.
"""
import collections
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "FDA_Drug_Advisories_Cleaned.csv"
out_path = ROOT / "assets" / "data" / "fda_advisories.json"
vocab_path = ROOT / "assets" / "tokenizer" / "vocab.json"
picker_path = ROOT / "lib" / "services" / "product_name_picker.dart"

CATEGORY = "Drug Advisories"

# Gate thresholds. Keep in sync with the doc comment on FdaDatasetChecker.
MIN_KEYS = 2
MIN_KEY_CHARS = 9
MIN_ANCHOR_LENGTH = 5
# A word appearing in more than this many distinct advisory names is not
# distinctive of any one of them ("otc", "balm", and brands like Betadine
# whose many counterfeit listings would otherwise flag the genuine product).
MAX_DOCUMENT_FREQUENCY = 8

# Words that describe a product without naming it, on top of the generic and
# descriptor sets shared with ProductNamePicker (read from its source below).
STOPWORDS = set("""
    otc rx injection injectable ampoule ampoules ampule vial vials cream creams
    ointment gel lotion oil oils liniment balm rub drops eye ear nasal spray
    syrup tablet tablets tab tabs capsule capsules cap caps solution powder
    granule granules sachet patch patches plaster pads soap tea pill pills
    suppository suppositories emulsion tincture enema inhaler inhale infusion
    drip syringe blister gummies liter liters litre gms grams bottle box
    pian jiaonang keli wan zhusheye zhusheyong koufuye koufu rongye san gao
    dan jiu shui ruangao ruanjiaonang penwuji wuji jiao nang yaoye
    package packaging insert label labels labeled labelled unlabeled foreign
    language chinese reflected primary secondary outer inner form sample front
    back side
    the and with for from per of unregistered brand product products posted
    natural naturals herbal organic premium supreme original extra strength
    strong forte plus max super new improved genuine pure fresh clear perfect
    better ultra triple essential essentials
    antibiotic antiseptic antibacterial bacteriostatic disinfectant sanitizer
    ophthalmic topical vaginal buccal intravenous veterinarian veterinary
    pharma pharm pharmaceutical pharmaceuticals medical medicated mentholated
    reliever suppressant rehydration probiotic gastrointestinal rheumatism
    rheuma hemorrhoids diaper germs regrowth drowsy lyophilized purified
    colloidal adsorbed herbaceous salts salt intramuscular subcutaneous use
    released
    alcohol ethyl isopropyl methyl salicylate menthol camphor eucalyptus
    peppermint citronella phenol chlorhexidine povidone iodine iodophor hydrogen
    peroxide dextrose lactate ascorbate bismuth disodium triphosphate taurine
    carnitine coenzyme gelatin pectin caffein dihydrochloride dipropionate
    enanthate estradiol ethinylestradiol bioflavonoids tetanus albumin insulin
    glutathione collagen
    watermelon cucumber sunflower guava ginger coconut moringa malunggay
    sambong oregano garlic turmeric aloe vera
    agua oxigenada aceite alcanforado alcamporado balsamo carminativo
    manzanilla soluzione iniettabile
    sildenafil tadalafil levonorgestrel flunarizine minoxidil cyproterone
    amantadine ivermectin finasteride bacitracin piroxicam naphazoline
    beclomethasone betamethasone dexamethasone hydrocortisone prednisolone
    triamcinolone fluocinonide clobetasol ketoconazole lignocaine lidocaine
    chloramphenicol colchicine methenamine furosemide famciclovir aciclovir
    acyclovir metoclopramide tacrolimus rifampicin imiquimod terbinafine
    mometasone reserpine triamterene favipiravir ribavirin polymyxin
    montmorillonite glycyrrhizinate clavulanate aminopyrine adenosine
    testosterone raceanisodamine belladonna tretinoin adapalene misoprostol
    merbromin aminophylline propionate benzalkonium sulfur benzoyl
""".split())

# INN stems specific enough to read as a generic, beyond ProductNamePicker's.
EXTRA_STEMS = ["mectin", "nafil", "sterone", "gestrel", "steride", "caine",
               "asone", "olone", "oquine"]

# Bracketed label annotations: "[as reflected in the package insert]",
# "(Label in Foreign language)", "(Secondary packaging)".
_annotation_re = re.compile(
    r"\[[^\]]*\]|\([^)]*(?:foreign|reflected|packaging|label)[^)]*\)", re.I)
_typed_mark_re = re.compile(r"(?<=[a-z])TM(?![A-Za-z])|\((?:R|TM)\)")
_ws_re = re.compile(r"\s+")
_word_re = re.compile(r"[^a-z0-9]+")


def _dart_string_set(source: str, name: str) -> list[str]:
    m = re.search(name + r"\s*=\s*<String>[{\[](.*?)[}\]];", source, re.S)
    if not m:
        sys.exit(f"Could not find {name} in {picker_path} — did it move?")
    body = re.sub(r"//[^\n]*", "", m.group(1))
    return re.findall(r"'([^']+)'", body)


def clean_name(raw: str) -> str:
    text = _annotation_re.sub(" ", raw.replace("\xa0", " "))
    text = text.replace("®", " ").replace("™", " ")
    # A trademark sign typed as letters: "MadenTM", "Albuked(R)".
    text = _typed_mark_re.sub(" ", text)
    return _ws_re.sub(" ", text).strip(" -–,:")


def words(text: str) -> list[str]:
    """Same split as FdaDatasetChecker._words: lowercase, alphanumeric runs,
    at least 3 characters."""
    return [w for w in _word_re.split(text.lower()) if len(w) >= 3]


def main() -> None:
    picker = picker_path.read_text(encoding="utf-8")
    generic_terms = set(_dart_string_set(picker, "kGenericTerms"))
    descriptor_terms = set(_dart_string_set(picker, "kDescriptorTerms"))
    stems = _dart_string_set(picker, "kGenericStems") + EXTRA_STEMS
    vocab = set(json.loads(vocab_path.read_text(encoding="utf-8")))

    def is_filler(word: str) -> bool:
        return (any(c.isdigit() for c in word)
                or word in STOPWORDS
                or word in generic_terms
                or word in descriptor_terms
                or (len(word) >= 7 and any(word.endswith(s) for s in stems)))

    with csv_path.open(encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))

    # One entry per distinct cleaned name; the first advisory listed wins.
    entries: dict[str, tuple[str, str, str]] = {}
    for row in rows:
        name = clean_name(row["Product Name"])
        if not name:
            continue
        entries.setdefault(name.upper(), (name, row["Advisory Number"].strip(),
                                          row["Date Posted"].strip()))

    doc_freq = collections.Counter(
        w for key in entries for w in set(words(key)))

    out = []
    for name, advisory, date in entries.values():
        keys = [w for w in dict.fromkeys(words(name))
                if not is_filler(w) and doc_freq[w] <= MAX_DOCUMENT_FREQUENCY]
        anchors = [w for w in keys
                   if len(w) >= MIN_ANCHOR_LENGTH and w not in vocab]
        if (len(keys) < MIN_KEYS
                or sum(map(len, keys)) < MIN_KEY_CHARS
                or not anchors):
            continue
        out.append([name, advisory, CATEGORY, date, keys, anchors])

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"), ensure_ascii=False)

    print(f"{len(rows)} CSV rows -> {len(entries)} distinct names -> "
          f"{len(out)} matchable entries written to {out_path}")


if __name__ == "__main__":
    main()
