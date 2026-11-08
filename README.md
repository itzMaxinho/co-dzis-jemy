# Co dziś jemy? — mobilna aplikacja domowego menu

Projekt jest przygotowany jako statyczny frontend + Supabase (PostgreSQL, Auth, Storage, Realtime). **Nie działa produkcyjnie po samym otwarciu `index.html`** — najpierw trzeba podłączyć własny projekt Supabase. Nie ma bezpiecznego sposobu na prawdziwe konta, bazę i powiadomienia w samym GitHub Pages bez backendu.

## Co jest w projekcie

- `index.html`, `style.css`, `app.js` — responsywna aplikacja mobile-first.
- `config.example.js` — szablon konfiguracji; skopiuj go jako `config.js`.
- `supabase.sql` — tabele, relacje, RLS, głosowanie, funkcje admina i bucket na zdjęcia.
- `assets/dishes/` — katalog na lokalne placeholdery/zdjęcia (zdjęcia dodawane z panelu admina trafiają do Supabase Storage).

## Uruchomienie backendu

1. Załóż bezpłatny projekt na https://supabase.com/ .
2. W Supabase otwórz **SQL Editor → New query**, wklej cały `supabase.sql` i uruchom.
3. W **Authentication → Providers → Email** wyłącz **Confirm email**. Aplikacja używa technicznego adresu e-mail generowanego z loginu (`login@users.co-dzis-jemy.app`), nie wysyła maili i nie wymaga skrzynki pocztowej. Nie zmieniaj domeny aliasu bez zmiany `alias()` w `app.js`.
4. W **Authentication → Settings → User Signups** pozostaw włączoną rejestrację, jeśli mają móc dołączać nowi goście.
5. Utwórz konto administratora w **Authentication → Users → Add user**:
   - Email: `oliwka@users.co-dzis-jemy.app`
   - Password: `mysia1` (Supabase wymaga co najmniej 6 znaków; `mysia` ma tylko 5).
   - zaznacz automatyczne potwierdzenie użytkownika (jeśli panel pokazuje taką opcję).
6. Wróć do SQL Editor i wykonaj:

   ```sql
   update public.profiles
   set username = 'oliwka', role = 'admin', nickname = 'Oliwka'
   where id = (select id from auth.users where email = 'oliwka@users.co-dzis-jemy.app');
   ```

7. **Zmień hasło administratora po pierwszym zalogowaniu** na mocne, unikalne hasło. `mysia1` jest wyłącznie hasłem startowym i jest zbyt łatwe do odgadnięcia. Po pierwszym logowaniu zmień je na mocne, unikalne hasło.
8. Z Supabase → **Project Settings → API** skopiuj Project URL i klucz `anon` / `publishable`.
9. Skopiuj `config.example.js` jako `config.js` i wstaw wartości:

   ```js
   window.APP_CONFIG = {
     SUPABASE_URL: 'https://....supabase.co',
     SUPABASE_ANON_KEY: 'eyJ...'
   };
   ```

   Klucz `anon`/`publishable` może być użyty w przeglądarce, bo bezpieczeństwo zapewnia RLS. **Nigdy nie umieszczaj `service_role` key w plikach strony.**
10. Otwórz lokalnie przez prosty serwer (np. VS Code Live Server), nie przez `file://`, albo opublikuj na hostingu.

## Hosting

Rekomendacja: **Cloudflare Pages + Supabase Free**. Repozytorium może być prywatne, Cloudflare Pages może pobierać kod z repozytorium GitHub i publikować stronę pod adresem `*.pages.dev`. Strona jest publicznie osiągalna pod adresem, ale sama zawartość aplikacji i dane są kontrolowane przez logowanie i polityki RLS. Nie wrzucaj danych prywatnych do publicznych plików.

GitHub Pages nie jest dobrym samodzielnym hostingiem tej aplikacji — to hosting statyczny, bez bazy i serwerowej logiki. Samo ukrycie repozytorium nie ukrywa opublikowanej strony.

## Ważne ograniczenia pierwszej wersji

To jest działający szkielet MVP z logowaniem, menu, ocenami, ulubionymi, prośbami, panelem admina, ankietą, powiadomieniami realtime i dźwiękiem. Przed użyciem przez większą grupę warto jeszcze rozszerzyć:

- reset hasła (bez e-maila wymaga osobnej procedury administratora),
- widok wyników ocen wszystkich użytkowników w panelu admina,
- listę głosów z ochroną przed obchodzeniem limitu przez zmianę przeglądarki/urządzenia (obecnie token przeglądarki; do silniejszej ochrony potrzebna weryfikacja np. CAPTCHA / rate limiting),
- automatyczne wywołanie `finish_expired_polls()` z harmonogramu Supabase, aby ankieta zamykała się dokładnie po 10 minutach nawet bez aktywnego użytkownika; obecny frontend również sprawdza termin przy wejściu do głosowania,
- edycję pseudonimu i usuwanie zdjęć po usunięciu dania.

## Bezpieczeństwo

- Hasła są przechowywane przez Supabase Auth (hashowane), nie w tabeli profili.
- Role admina nie są ustawiane przez formularz rejestracji. Ustawia je właściciel bazy SQL.
- RLS ogranicza odczyt i modyfikację prywatnych danych.
- Nie udostępniaj nikomu `service_role` key.

### Automatyczne zamykanie ankiet

Aplikacja sprawdza upływ czasu co 15 sekund, kiedy ktoś ma otwartą stronę. Aby ankieta kończyła się również wtedy, gdy nikt nie ma otwartej strony, w Supabase włącz rozszerzenie `pg_cron` (Database → Extensions), a następnie uruchom:

```sql
select cron.schedule(
  'finish-expired-polls-every-minute',
  '* * * * *',
  $$ select public.finish_expired_polls(); $$
);
```

Harmonogram sprawdza terminy co minutę, więc w tle zakończenie może nastąpić do około minuty po upływie 10 minut. Przy aktywnych użytkownikach frontend sprawdza to częściej.
