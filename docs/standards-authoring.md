# Pisanie sprawdzalnych standardów — ContextForge

Właściciel dokumentu: Łukasz Parfieniuk. Przegląd źródeł: 2026-10-08.

Ten dokument służy zapisywaniu powodów, dla których stosuję zasady, oraz ćwiczeniu
przekładania ich na jednoznaczne wymagania. Karty poniżej formalizują istniejące
praktyki; nie zastępują `core/rules/`, indeksu ani instrukcji projektu. Nowe pomysły
mają status `draft` do czasu decyzji właściciela i wdrożenia w odpowiednim źródle.

## Jak zapisać następną zasadę

1. Opisz konkretny problem i koszt zaniechania. Zapisz również koszt samej zasady.
2. Ustal zakres: obiekt, moment sprawdzenia i osobę odpowiedzialną.
3. Zapisz jedno wymaganie. Rozdziel zdanie zawierające kilka niezależnych warunków.
4. Dopisz wynik kontroli, przykład poprawny, błędny i przypadek brzegowy.
5. Wskaż źródło, kontrolę i dowód wykonania. Brak któregoś z nich oznacz wprost.
6. Po zmianie źródła przejrzyj kartę. Historia zmian wyjaśnia decyzję i jej powód.

W tym dokumencie `MUST` oznacza obowiązek, `SHOULD` zalecenie dopuszczające
uzasadnione odstępstwo, a `MAY` opcję. Znaczenia pochodzą z
[RFC 2119](https://www.rfc-editor.org/info/rfc2119/) i
[RFC 8174](https://www.rfc-editor.org/rfc/rfc8174.html).
To słownik zapisu, nie mechanizm wymuszania zachowania.

## Szablon karty

```markdown
### <ID> — <krótka nazwa>

- Wersja / status: 1 / draft | formalizacja istniejącej zasady | accepted | retired.
- Właściciel / data przeglądu: <osoba> / <YYYY-MM-DD>.
- Problem i uzasadnienie: <konkretny tryb awarii, któremu zapobiegam>.
- Zakres: <jakie obiekty, kiedy, dla którego narzędzia lub procesu>.
- Wymaganie: <obiekt> MUST/SHOULD/MAY <jeden obserwowalny warunek>.
- Źródło decyzji: <link do reguły, ADR albo decyzja właściciela>.
- Kontrola: <automatyczna | ręczna | brak; plik i nazwa testu albo procedura>.
- Kryterium zaliczenia: <jednoznaczny wynik kontroli>.
- Dowód: <commit, polecenie, rzeczywisty exit code, raport; albo nie wykonano>.
- Zgodny przykład: <minimalny przypadek spełniający warunek>.
- Niezgodny przykład: <minimalny przypadek łamiący warunek>.
- Edge case: <granica zakresu albo przypadek nieocenialny>.
- Wyjątek: <kto zatwierdza, powód, zakres, termin wygaśnięcia; albo brak>.
- Koszt / ograniczenie: <co tracę albo czego kontrola nie dowodzi>.
- Historia: <data — zmiana, powód; przy odwróceniu decyzji wskaż wcześniejszą>.
```

Zapis kontroli i dowodu jest rozdzielony: znaleziony test nie oznacza, że został
uruchomiony. Wynik kontroli to `pass`, `fail` albo `not-assessed`. Zatwierdzony
wyjątek zapisuję osobno; nie zmieniam przez niego wyniku testu na `pass`.

## Karty z istniejących praktyk

### CF-STD-001 — Rejestracja źródła reguły

- Wersja / status: 1 / formalizacja istniejącej zasady.
- Właściciel / przegląd: Łukasz Parfieniuk / 2026-10-08.
- Problem: plik poza rejestrem może zostać pominięty przy dystrybucji.
- Zakres: nowa reguła runtime ContextForge, przed utworzeniem pliku źródłowego.
- Wymaganie: nowa reguła MUST mieć wpis w `core/_index.yaml` przed utworzeniem
  jej pliku źródłowego.
- Źródło: globalna zasada rozwoju ContextForge; [indeks](../core/_index.yaml).
- Kontrola: ręczna dla kolejności zmian; pomocniczo
  [validate-index.sh](../core/scripts/tools/validate-index.sh) sprawdza istniejące
  odwołania do plików. Sam końcowy indeks nie dowodzi kolejności utworzenia.
- Kryterium: historia zmian pokazuje rejestrację przed utworzeniem źródła.
- Dowód: przegląd źródła kontrolera; historii konkretnej nowej reguły nie oceniano.
- Zgodny przykład: najpierw wpis w indeksie, następnie plik we wskazanej ścieżce.
- Niezgodny przykład: utworzenie reguły, a później dopisanie jej do indeksu.
- Edge case: dokument w `docs/` nie staje się regułą runtime przez użycie `MUST`.
- Wyjątek: brak w tej karcie; zmianę procesu podejmuje właściciel.
- Koszt / ograniczenie: dodatkowy krok; walidator sprawdza stan, nie historię.
- Historia: 2026-10-08 — zapis istniejącej zasady i granicy automatycznej kontroli.

### CF-STD-002 — Koszt reguł ładowanych zawsze

- Wersja / status: 1 / formalizacja istniejącej zasady.
- Właściciel / przegląd: Łukasz Parfieniuk / 2026-10-08.
- Problem: reguła potrzebna tylko w wybranych zadaniach obciąża każdą sesję.
- Zakres: indeksowane reguły dla emitera Claude Code, przy walidacji dystrybucji.
- Wymaganie: reguła z niepustym `installed_claude` MUST mieć `activation: always`.
- Źródło: kontrakt aktywacji w [CLAUDE.md](../CLAUDE.md).
- Kontrola: automatyczna w
  [rule-activation.test.ts](../scripts/rule-activation.test.ts), test
  `only \`always\` rules occupy .claude/rules/ (always-on cost)`.
- Kryterium: test znajduje zero reguł z instalacją Claude i inną aktywacją.
- Dowód: kontrola odczytana w źródle; testu nie uruchomiono podczas pisania karty.
- Zgodny przykład: reguła on-demand ma `installed_claude: null`.
- Niezgodny przykład: reguła on-demand ma ścieżkę w `.claude/rules/`.
- Edge case: osierocony plik instalacji wymaga osobnej kontroli katalogu; test
  indeksu sam go nie wykrywa. Inny harness wymaga kontroli swojego emitera.
- Wyjątek: brak; rozszerzenie zakresu ładowania wymaga zmiany decyzji źródłowej.
- Koszt / ograniczenie: reguła on-demand może nie zostać odczytana przez agenta.
- Historia: 2026-10-08 — oddzielono kontrolę indeksu od kontroli plików i zachowania.

### CF-STD-003 — Zakres twierdzenia o egzekwowaniu reguły

- Wersja / status: 1 / draft; propozycja doprecyzowania sposobu raportowania.
- Właściciel / przegląd: Łukasz Parfieniuk / 2026-10-08.
- Problem: poprawna instalacja instrukcji może zostać pomylona z jej przestrzeganiem.
- Zakres: raport twierdzący, że agent przestrzega konkretnej reguły.
- Wymaganie: raport MUST wskazywać dowód obserwowanego zachowania agenta
  dotyczący tej reguły, aby uzasadniać twierdzenie o jej przestrzeganiu.
- Źródło decyzji: propozycja tej karty; punktem odniesienia jest
  [check-parity.sh](../core/scripts/tools/check-parity.sh), który bada instalację
  i zawsze zwraca 0 jako wynik informacyjny.
- Kontrola: ręczny przegląd twierdzenia, obserwacji i jej zakresu; brak gate'u.
- Kryterium: dowód obejmuje oceniane zachowanie, warunki oraz granicę wniosku.
- Dowód: brak eksperymentu zachowania dla tej karty; `not-assessed`.
- Zgodny przykład: „W scenariuszu X hook zablokował operację Y; zapis zdarzenia Z”.
- Niezgodny przykład: „parity zakończyło się kodem 0, więc agent przestrzega reguł”.
- Edge case: pomiar bez potrzebnej obserwacji pozostaje nieoceniony, nie zaliczony.
- Wyjątek: brak; wniosek można zawęzić do poprawności instalacji.
- Koszt / ograniczenie: zebranie obserwacji kosztuje; pojedynczy scenariusz nie
  dowodzi skuteczności we wszystkich zadaniach.
- Historia: 2026-10-08 — propozycja, bez zmiany aktywnych reguł i hooków.

## Ćwiczenie: od hasła do wymagania

Weź jedną zasadę, np. „używaj najtańszego poprawnego wykonawcy”. Napisz kartę
`CF-STD-004` ze statusem `draft`. Najpierw określ, co oznacza „poprawny”, jak
porównujesz koszt i co robisz, gdy jednej wielkości nie znasz. Przygotuj przypadek,
w którym tańszy wykonawca kosztuje ostatecznie więcej przez ponawianie pracy.

Poproś czytelnika o ocenę trzech przypadków wyłącznie na podstawie karty. Jeżeli
musicie dopowiadać definicję, popraw wymaganie. Wywiad z ekspertem ćwiczy ustalenie
tej definicji, a test sprawdza dopiero uzgodnioną treść.

Na potrzeby nauki można użyć lokalnych poziomów:
- **baseline:** jedno wymaganie, zakres, źródło oraz kryterium zaliczenia;
- **enhanced:** dodatkowo przykłady, edge case i określona obsługa wyjątku;
- **evidenced:** dodatkowo rzeczywisty dowód wykonania kontroli dla danej wersji.

To propozycja oceny kompletności kart, nie certyfikat zgodności projektu. Kartę
`draft` oceniam jako ćwiczenie; samo wypełnienie pól nie zatwierdza jej do runtime.

Przykłady pomiarowe: [rejestr cf-bench](../../ai-tools/cf-bench/docs/standards-authoring.md).
Link między lokalnymi repozytoriami zakłada układ katalogów `Projects`; po
publikacji osobnych repozytoriów ich README pozostają punktami wejścia.

## Historia dokumentu

- 2026-10-08 — pierwszy zapis: wspólny szablon, dwa przykłady istniejących zasad,
  jedna propozycja i ćwiczenie. Bez zmian w źródłach runtime.
