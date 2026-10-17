# Datenbank für Caltera City Forum einrichten

Die Website ist aktuell eine statische GitHub-Pages-Seite und speichert Daten lokal. Diese SQL-Datei erstellt die gemeinsame Datenbankstruktur in Supabase mit Profilen, Foren-Themen, Antworten, Rollen und Auszeichnungen. Supabase empfiehlt Row Level Security für alle Tabellen, die über die Data API erreichbar sind; das Schema aktiviert RLS und begrenzt Lese- und Schreibrechte.

## Supabase-Projekt vorbereiten

1. Lege ein Supabase-Projekt an.
2. Öffne **SQL Editor → New query**.
3. Füge den Inhalt aus `supabase/schema.sql` ein und führe ihn aus.
4. In **Project Settings → API Keys** kopiere Projekt-URL und `publishable` key (früher `anon` key). Niemals `service_role` oder `secret` key in die Website einfügen.

## Danach

Die Datenbank ist damit erstellt, aber die Website benötigt noch Projekt-URL und publishable key, und ihr Datenzugriff muss auf Supabase umgestellt werden. Sende mir die Projekt-URL und den publishable key, dann kann ich die Website verbinden. Diese Werte sind für eine Browser-App bestimmt. Schicke niemals dein Supabase-Passwort oder einen `service_role`/`secret` key.

## Ersten Inhaber setzen

Registriere zuerst dein Konto mit Supabase Auth. Danach setze die `role` deines Profils im Supabase Table Editor auf `Inhaber`. So liegt der Inhaberzugang serverseitig und nicht als öffentlich lesbarer Code im JavaScript.
