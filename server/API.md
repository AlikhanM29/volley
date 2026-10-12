# Volley API v2

Барлық API жолдары `/api` префиксімен басталады. JSON сұраулары: `Content-Type: application/json`. Авторизация: браузерде HttpOnly cookie, native клиентте `Authorization: Bearer <token>`. Сервер әр сұрауда дерекқордан белсенді пайдаланушы мен оның рөлін тексереді.

## Рөлдер

| Рөл | Құқық |
|---|---|
| Қонақ / user | Қоғамдық оқу; тіркелсе өз профилі, шақырулар және хабарламалар |
| coach | Пайдаланушы құқықтары; тек өз командасын құру/өңдеу, шақыру, құрам, капитан |
| admin | Командалар, пайдаланушылар, матчтар, турнирлер, кодтар, журнал |

Қонақ — тіркелмеген пайдаланушы, жеке `guest` рөлі жоқ. `organizer` және `player` рөлдері енді қолданылмайды. Админ құқықтары тек код арқылы беріледі.

## Аккаунт

- `POST /register`: `{name,email,password,phone?,role:"user"|"coach",admin_code?}`. Admin коды тек user тіркелуімен бірге. Кодты қолдану және аккаунт жасау бір транзакцияда орындалады.
- `POST /login`: `{email,password}` → `{user,token}`.
- `POST /logout`: сессияны жою.
- `GET /me` → `{user,team}`. Coach үшін `team:null` болса, клиент міндетті команда жасау экранын көрсетеді.
- `PATCH /me`: `{name,phone}`.
- `POST /admin/redeem`: `{code}`. Қолданыстағы user аккаунтына admin құқығын беру. Командасы бар coach алдымен оны басқа жаттықтырушыға тапсыруы керек.

## Командалар мен шақырулар

- `GET /teams`, `GET /teams/:id`: командалар және қабылданған құрам. Email/телефон қоғамдық құрамда көрсетілмейді.
- `POST /teams`, `PATCH /teams/:id`: `{name,city,description,logo?}`. `logo` — HTTPS сурет URL. Админ қосымша `coach_id`, `active:0|1` бере алады. Әр жаттықтырушыға бір команда.
- `DELETE /teams/:id`: admin; жұмсақ жою, ашық шақыруларды тоқтату. Тарихи матчтар сақталады.
- `GET /users/search?q=...`: coach/admin; кемінде екі таңба, 20 нәтиже. Аты, email, телефон, профиль ID. Тек тіркелген белсенді user аккаунттары.
- `POST /teams/:id/invitations`: `{user_id}`. Coach тек өз командасына; admin кез келген командаға. Бір team/user жұбына қайталанатын шақыруға тыйым салынған, қабылданбаған шақыруды да қайта жіберу мүмкін емес.
- `GET /teams/:id/invitations`: басқарушыға жіберілген шақырулар.
- `GET /invitations`: тек өзіне арналған шақырулар.
- `PATCH /invitations/:id`: `{status:"accepted"|"rejected"}`; тек шақырылған адам. Қабылдау мен membership жасау атомарлық.
- `PATCH /teams/:id/members/:userId`: `{captain:0|1}`; капитан тек бар құрамнан. Бір командада бір капитан.
- `DELETE /teams/:id/members/:userId`: ойыншыны шығару.
- `GET /notifications`, `POST /notifications/:id/read`: жеке хабарламалар. Клиент әр 20 секундта жаңартады, профильге кіргенде және қолдан жаңартқанда да жүктейді.

## Матчтар

- `GET /matches`: жойылмаған матчтар.
- `POST /matches`: admin, `{team_a,team_b,start_at,location,format:"indoor"|"beach",best_of:1|3|5}`. Командалар тіркелген, белсенді және әртүрлі болуы керек.
- `PATCH /matches/:id`: уақыт/орын; жеке матчта командалар/формат та өзгертіледі. Турнирдің командалары автоматты кестемен анықталады. Аяқталған матч метадеректері бекітілген.
- `POST /matches/:id/result`: `{score_a,score_b}`; жеңімпаз `(best_of+1)/2` сет алуы керек. Келесі матч аяқталмаса нәтижені түзетуге болады. Жеңімпаз келесі слотқа сервер арқылы өтеді.
- `DELETE /matches/:id`: жұмсақ жою және келесі матчтан жеңімпазды алып тастау. Келесі матч аяқталған болса операция бұғатталады. Кестеде жойылған түйін көрсетіледі, оны өткізу арқылы жалған жеңімпаз шығарылмайды.

`start_at` — уақыт белдеуі көрсетілген ISO 8601, сервер UTC минутына нормалайды. Бір команданың дәл сол минуттағы екінші матчына тыйым салынады. Бұл ұзақтығы бойынша қабаттасу емес, басталу уақытының қақтығысын тексеру. Плей-оффтың белгісіз болашақ слоттары үшін де ықтимал қатысушылардың уақыты резервтеледі.

## Турнирлер

- `GET /tournaments`, `GET /tournaments/:id`: команда тізімі, матчтар, раундтар және standings.
- `POST /tournaments`: admin, `{title,team_ids:[...],kind:"round_robin"|"playoff",start_at,location,format,best_of,round_minutes}`. 2–32 команда, кемінде 30 минуттық раунд аралығы.
- `PATCH /tournaments/:id`: жасалмаған кесте үшін барлық баптау; генерациядан кейін тек атауы мен турнирдің орны. Жеке матчтың орны бөлек өңделеді.
- `POST /tournaments/:id/generate`: «Матчтарды автоматты түрде жасау». Бір рет, бір транзакцияда; қақтығыс болса жартылай матчтар сақталмайды.
- `DELETE /tournaments/:id`: турнир мен матчтарын жұмсақ жою.

Айналмалы алгоритмде әр жұп бір рет ойнайды, тақ сан кезінде бос кезек болады. Плей-офф келесі екі дәрежесіне толықтырылады; bye жеңімпазы келесі кезеңге автоматты өтеді. Жеңімпаздың алға өтуі атомарлық. 5 сеттік матчтарда 3:2 нәтижесі — 2/1 ұпай, қалған жеңістер — 3/0. Қалған форматтарда жеңіс — 3 ұпай. Рейтинг: ұпай, жеңіс, сет айырмасы; тең көрсеткіштер аты бойынша көрсетіледі (қосымша спорттық тай-брейк жоқ).

## Администратор

- `GET /admin/users`, `PATCH /admin/users/:id`: `{name?,phone?,active?}`. Құқық көтеретін role өрісі қабылданбайды. Бұғаттау сессияларды жояды; соңғы белсенді админ бұғатталмайды.
- `POST /admin/codes`: `{max_uses:1..20,hours:1..168}` → код бір рет көрсетіледі.
- `GET /admin/codes`: кодтың тек метадеректері, хеш те берілмейді.
- `DELETE /admin/codes/:id`: кері қайтарып алу; аудит үшін жазба сақталады.
- `GET /admin/audit`: соңғы 200 әрекет. Код жасау/қайтарып алу және admin құқық беру әрқашан журналданады, бастапқы код ешқашан журналға жазылмайды.
- `GET /admin/legacy`: алдыңғы схемадағы турнир архиві.

## Дерекқор

| Кесте | Негізгі байланыстар/шектеулер |
|---|---|
| users | id PK, email UNIQUE, user/coach/admin, password salt+hash, active |
| sessions | SHA-256 token PK, user FK, expires |
| teams | coach_id UNIQUE FK, атау/қала/сипаттама/логотип, active/deleted |
| memberships | PK(team,user), FK; командада бір капитан |
| invitations | UNIQUE(team,user); pending/accepted/rejected/cancelled |
| notifications | recipient user FK, invitation FK, read_at |
| admin_codes | code hash UNIQUE, issuer FK, expires, max_uses, uses, revoked |
| audit_log | actor FK, action, target, JSON details, timestamp |
| tournaments | kind, schedule, generated/deleted, creator FK |
| tournament_teams | PK(tournament,team), UNIQUE(tournament,seed) |
| matches | team FKs, tournament FK, next_match self FK, next_slot, scores |
| schema_migrations | қолданылған нұсқалар |
| legacy_tournaments | ескі JSON турнирлер, өзгертілмейтін архив |

Өзара байланысты өзгерістер `BEGIN IMMEDIATE` транзакцияларымен қорғалған. FK/UNIQUE/CHECK индекстері қолданба тексерулерін толықтырады. Миграцияны іске қосу: `node server/migrate.mjs`; сервер іске қосылғанда да орындалады.
