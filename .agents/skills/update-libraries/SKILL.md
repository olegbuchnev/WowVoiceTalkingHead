---
name: update-libraries
description: Update and audit the WowVoice, CatQuest and Wayfarer voice libraries and shared quest text/NPC metadata for TalkingHead Ru, including Forever Quest Pins. Use when these libraries change or the user asks to refresh their imported data.
---

# Обновление библиотек TalkingHead Ru

Работай из корня текущей копии репозитория TalkingHead Ru, содержащего этот скилл
в `.agents/skills/update-libraries/`.
Прочитай его `BUILD.local.md` и соответствующие разделы `docs/DEVELOPMENT.md`.
Для Wayfarer смотри также `docs/internal/wayfarer-integration.md`.
Команды ниже выполняются из корня проекта. Пути к установленным аддонам берутся
из `config/build.env.local.ps1`, переменная `WOWVOICE_FOREVER_BETA_ADDONS`.

## Определить изменения

- Сверь версии и фактические данные, а не только номер релиза. CatQuest и
  CatQuest_Voices обновляются независимо; обновление ядра может менять NPC без
  изменения аудио. Wayfarer хранит NPC в индексах голосовых пакетов.
- Выполни `build.cmd -Task CheckSources`: Forever Quest Pins проверяется отдельно
  через GitHub по `Database/ForeverQuests.lua`. Результат хранится в
  `artifacts/review/forever-pins-update.json`. `unavailable` не означает актуальность:
  сообщи об этом и повтори проверку перед выпуском. Другие локальные проверки
  можно продолжить.
- Перед импортом сохрани изменяемые метаданные в отдельную папку
  `artifacts/review/`, чтобы сравнить результат. Не редактируй установленные
  сторонние аддоны, их TOC, индексы и звуковые файлы.
- Источники разбираются как данные: не исполняй сторонний Lua. Не подменяй
  проверку файлов одним обновлением поля версии.

## Импортировать затронутые данные

- **WowVoiceSounds:** `node tools/generate-classic-metadata.js <WowVoiceSounds>`;
  сверка без записи: та же команда с `--check`. Читай OGG напрямую из установленной
  библиотеки; сохраняй только `src/Durations.lua` и манифест измерений.
- **CatQuest Voices:** `node tools/import-forever-audio.js <CatQuest_Voices>`.
- **CatQuest NPC:** `node tools/import-catquest-speakers.js <CatQuest>`.
  Если изменился только `NpcData.lua`, не требуется перегенерировать аудио.
- **Wayfarer:** после обновления голосовых пакетов выполни все три импорта:
  `node tools/generate-wayfarer-metadata.js <AddOns>`,
  `node tools/import-quest-texts.js <AddOns>`,
  `node tools/import-wayfarer-speakers.js <AddOns>`.
  Последний читает `qg`, `npc` и говорящих `q[id].a/p/c.s`; даёт связи выдачи/сдачи,
  имена и облики. Не заменяй отсутствующего принимающего выдающим NPC и не
  назначай рассказчику NPC. Импорт NPC не требует OGG и может запускаться отдельно.
- **Forever Quest Pins:** при `changed` получи `Database/ForeverQuests.lua` и
  `Database/Metadata.lua` из одного указанного коммита. Запусти
  `node tools/import-forever-pins-speakers.js <Database> <полный-SHA>`.
  Старый подробный снимок Forever остаётся отдельным резервным источником.

Все импорты NPC пересобирают единую `src/Speakers.lua`. В игре нет обхода
отдельных баз по очереди. Источники и решения фиксируются в
`docs/internal/speakers-manifest.json`.

Все библиотеки озвучки остаются внешними. Не копируй их OGG в проект,
`backups`, `artifacts` или релиз. Единственный собственный звуковой файл —
`src/Media/silence.ogg`; для релиза используется только `PackageAddon`.

## Приоритеты, согласованные с пользователем

Основной критерий — частота поддержки источника. Порядок фиксирован в
`tools/generate-speakers.js`; номера версий разных проектов не сравниваются.

- Выдающие NPC: CatQuest → Wayfarer → актуальные Pins → старый Forever → Classic.
- Принимающие NPC: CatQuest → Wayfarer → Classic.
- Облики: CatQuest → Wayfarer, только по точному ID NPC.
- Имена: предпочитать русские; при равном языке CatQuest → Wayfarer → Classic → старый Forever.
- Явные сведения о предмете, объекте или нескольких/противоречивых квестодателях
  защищены от замены одиночным NPC; отсутствие сведений позволяет следующий источник.
- В игре фактически полученные NPC и облики выше общей базы на любом языке.
  Резервные модели не записываются в наблюдения персонажа. Поздняя загрузка
  реальной модели должна обновлять исходную запись и показанный портрет.
- Приоритет озвучки в настройках не меняет текстовую базу или выбор NPC.
  Порядок текстов остаётся WowVoice → CatQuest → Wayfarer; на ruRU игровой текст
  выше базы, на enUS/enGB русский текст базы выше игрового.

## Проверить результат

Запусти `node tools/generate-speakers.js --check` и
`node tools/import-wayfarer-speakers.js <AddOns> --check` для установленных пакетов.
При обновлении WowVoiceSounds выполни
`node tools/generate-classic-metadata.js <WowVoiceSounds> --check`.
Общие тесты проверяют согласованность сохранённых метаданных без библиотек;
сверка реальных OGG выполняется этой отдельной командой по установленной библиотеке.
После всех затронутых импортов CatQuest запусти
`node tools/audit-catquest.js <CatQuest> <CatQuest_Voices>` и
`node tools/check-catquest-compatibility.js <CatQuest_Voices>`.
При изменении аудио Wayfarer используй также
`node tools/check-wayfarer-compatibility.js <AddOns>`.
Проверь изменения количества NPC/связей/обликов, `protectedExclusions`,
`conflicts` и `appearanceConflicts` в отчёте. Конфликты разрешаются согласованным
порядком; отчёт позволяет объяснить выбор, а не требует вручную выбрать каждый NPC.

Для изменений генератора запусти соответствующие тесты импорта; после изменения
общих runtime-данных — `node tests/run.js`, перед выпуском — `build.cmd -Task Test`.
Обнови текущие инструкции и данные версий в документации, не переписывая
исторические отчёты прошлых миграций. Отдельно укажи, что проверено автоматически
и что проверено в игре. Установка в клиент и публикация выполняются в рамках
запрошенной пользователем задачи, а не автоматически из-за запуска скилла.
