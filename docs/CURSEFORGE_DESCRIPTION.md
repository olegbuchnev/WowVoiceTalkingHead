# TalkingHead Ru — Russian quest voiceovers for WoW Forever

**TalkingHead Ru** brings Russian quest voiceovers to **WoW Forever** with a Retail-style talking head. During playback, the addon displays an animated character portrait, the speaker’s name, and dialogue text.

> ⚠️ **VOICE LIBRARY REQUIRED**
>
> Voice recordings are downloaded separately. Install **at least one** of these options:
>
> * **[WowVoice](https://www.curseforge.com/wow/addons/wowvoice-classic)**
> * **[CatQuest](https://www.curseforge.com/wow/addons/catquest) + [CatQuest Voices](https://www.curseforge.com/wow/addons/catquest-voices)** — both addons are required.
> * **[Wayfarer](https://www.curseforge.com/wow/addons/wayfarer-russian-voiceover) + quest voice modules** — installing all three modules is strongly recommended: **[Alliance](https://www.curseforge.com/wow/addons/wayfarer-voices-alliance)**, **[Horde](https://www.curseforge.com/wow/addons/wayfarer-voices-horde)**, and **[Shared Quests](https://www.curseforge.com/wow/addons/wayfarer-voices-shared-quests)**.
>
> For the widest quest coverage, install all three voice libraries.
>
> **Without a voice library, quest voiceovers and talking heads are unavailable.**

<img src="https://olegbuchnev.github.io/WowVoiceTalkingHead/images/talking-head-dwarf.56baa2bfa9f1c29c7c84168632ca868ee8f5fcb75db951a8a68f5fda079cbfc5.png" alt="Talking head — Sten Stoutarm" width="800">

## Features

* **Retail-style talking head.** Adjust the panel’s position and scale to fit your interface.
* **Three voice libraries.** Use WowVoice, CatQuest, and Wayfarer in any combination. Coverage varies: not every quest stage or line is voiced.
* **Voice selection by race and sex.** Community rankings choose the library by default. Set a personal order for individual groups or use one order for all voices. If a recording is unavailable, TalkingHead Ru checks the next library.
* **Updated community rankings.** Import a ranking string from the voting site. Personal group orders are preserved by default.
* **Voice library label.** Optionally show the source library on the talking head; disabled by default.
* **Configurable automatic playback.** Enable or disable voiceovers separately for quest acceptance and turn-in.
* **Replay quest descriptions.** Use the ▶ buttons in the quest log, the standard quest tracker, or Questie Tracker.
* **Quest progress reminders.** A highlighted replay button reminds you of a description you have not listened to.
* **Voice comparison.** Browse the built-in catalogue to listen to and compare recordings from all three libraries.
* **Shared Russian quest texts.** Texts imported from the voice libraries are stored in a shared database. Changing voice priority does not change the quest text.

## Playback queue

Accepted quests and turn-in lines are grouped by quest giver. Play any recording immediately, move it next, or listen to the queue in order.

Disable automatic queue playback to let the current recording finish and start the next one manually. Clear the queue to remove all entries and stop playback.

<img src="https://olegbuchnev.github.io/WowVoiceTalkingHead/images/quest-queue-controls.19bb71da7b8d0f54a55f59b42280280c0ec666b6b450b7fc2a48a2d8ee7a49d3.png" alt="Playback queue and controls" width="500">

## Voice sources

* **[WowVoice](https://www.curseforge.com/wow/addons/wowvoice-classic)** — classic quest voiceovers with **3,669 main quest descriptions**.
* **[CatQuest](https://www.curseforge.com/wow/addons/catquest) + [CatQuest Voices](https://www.curseforge.com/wow/addons/catquest-voices)** — alternative voiceovers and additional Forever quests, with **4,473 main quest descriptions**.
* **[Wayfarer](https://www.curseforge.com/wow/addons/wayfarer-russian-voiceover)** — Alliance, Horde, and shared quest voiceovers, with **3,790 main quest descriptions** across three modules.

These counts include only main quest descriptions, excluding progress lines, turn-ins, and additional gender variants. Some quests are available in multiple libraries.

For Wayfarer, enable the main addon and its quest voice modules. **Installing all three modules is strongly recommended:**

* **[Wayfarer Voices - Alliance](https://www.curseforge.com/wow/addons/wayfarer-voices-alliance)**
* **[Wayfarer Voices - Horde](https://www.curseforge.com/wow/addons/wayfarer-voices-horde)**
* **[Wayfarer Voices - Shared Quests](https://www.curseforge.com/wow/addons/wayfarer-voices-shared-quests)**

The Narrator module is not required for quest voiceovers. If some quest modules are missing, a warning on the Wayfarer card lists them.

Use community rankings by race and sex, set personal group orders, or choose one global library order in settings. Ties and groups without ratings use your global order. Unavailable libraries are skipped without changing your saved priority. Lines without an available recording are skipped.

## Compatibility

While TalkingHead Ru is enabled, CatQuest and Wayfarer are used as voice libraries: automatic playback, quest playback buttons and automatic notifications are suppressed. Manual book reading and location lore remain available. If you enable location lore, its indicator or CatQuest world voices again in the library's settings, TalkingHead Ru remembers that choice and stops overriding it, including after a restart.

Disabling TalkingHead Ru restores only the settings it still controls, preserving your explicit lore preferences. The startup message includes links only for loaded voice libraries.

The original WowVoice player is disabled automatically to prevent duplicate playback. Its **WowVoiceSounds** library stays enabled.

Replay buttons support the standard quest tracker, including EllesmereUI styling, and Questie Tracker. Custom quest lists from other addons may not display these buttons.

## Installation and settings

1. Install **TalkingHead Ru** for **WoW Forever**.
2. Install **at least one voice library**: **WowVoice**, **CatQuest + CatQuest Voices**, or **Wayfarer with quest voice modules**. For the widest coverage, install all three libraries. For Wayfarer, all three quest modules are strongly recommended.
3. Fully restart the game and enable TalkingHead Ru and the required library addons in the AddOns list.
4. Type **`/thead`** or open **Options → AddOns → TalkingHead Ru** to access settings.

Settings let you arrange voice library priority, configure automatic playback and the queue, and adjust the talking head’s position and scale.

Fully restart the game after installing or updating voice libraries so the client can detect new sound files.

On English clients, player controls use English; settings and the voice catalogue remain in Russian. Russian quest text from the shared database is used when available.

[Website and instructions](https://olegbuchnev.github.io/WowVoiceTalkingHead/) · [Report an issue](https://github.com/olegbuchnev/WowVoiceTalkingHead/issues)

***

# TalkingHead Ru — русская озвучка заданий для WoW Forever

**TalkingHead Ru** — русская озвучка заданий для **WoW Forever** с говорящей головой в стиле Retail. Во время воспроизведения на экране отображаются анимированный портрет персонажа, его имя и текст реплики.

> ⚠️ **НУЖНА БИБЛИОТЕКА ОЗВУЧКИ**
>
> Записи скачиваются отдельно. Установите **хотя бы один** из этих вариантов:
>
> * **[WowVoice](https://www.curseforge.com/wow/addons/wowvoice-classic)**
> * **[CatQuest](https://www.curseforge.com/wow/addons/catquest) + [CatQuest Voices](https://www.curseforge.com/wow/addons/catquest-voices)** — нужны оба аддона.
> * **[Wayfarer](https://www.curseforge.com/wow/addons/wayfarer-russian-voiceover) + квестовые голосовые модули** — настоятельно рекомендуется установить все три модуля: **[Alliance](https://www.curseforge.com/wow/addons/wayfarer-voices-alliance)**, **[Horde](https://www.curseforge.com/wow/addons/wayfarer-voices-horde)** и **[Shared Quests](https://www.curseforge.com/wow/addons/wayfarer-voices-shared-quests)**.
>
> Для максимального охвата заданий рекомендуется установить все три библиотеки озвучки.
>
> **Без библиотеки озвучка и говорящая голова для заданий недоступны.**

<img src="https://olegbuchnev.github.io/WowVoiceTalkingHead/images/talking-head-dwarf.56baa2bfa9f1c29c7c84168632ca868ee8f5fcb75db951a8a68f5fda079cbfc5.png" alt="Говорящая голова — Стен Крепкорук" width="800">

## Возможности

* **Панель в стиле Retail.** Положение и масштаб говорящей головы можно изменить под свой интерфейс.
* **Три библиотеки озвучки.** Подключайте WowVoice, CatQuest и Wayfarer в любом сочетании. Набор записей зависит от задания: озвучены не все этапы и реплики.
* **Выбор озвучки по расе и полу.** По умолчанию библиотека выбирается по рейтингу сообщества. Можно настроить личный порядок для отдельных сочетаний или один порядок для всех. Если записи нет, TalkingHead Ru проверит следующую библиотеку.
* **Обновление рейтинга сообщества.** Импортируйте строку с сайта голосования. Личные порядки по умолчанию сохраняются.
* **Название библиотеки на говорящей голове.** Отображение источника озвучки включается в настройках; по умолчанию выключено.
* **Настраиваемый автозапуск.** Озвучку при получении и сдаче задания можно включать и отключать независимо друг от друга.
* **Повторное прослушивание.** Кнопки ▶ в журнале, стандартном трекере и Questie Tracker позволяют включить описание без возвращения к квестодателю.
* **Напоминание при прогрессе задания.** Подсветка кнопки напоминает о непрослушанном описании.
* **Сравнение озвучек.** Во встроенном каталоге «Послушать озвучку» можно прослушать задания и сравнить записи всех трёх библиотек.
* **Общая база русских текстов.** Тексты из библиотек озвучки собраны в собственную базу. Изменение приоритета озвучки не меняет текст задания.

## Очередь воспроизведения

Принятые задания и реплики сдачи группируются по квестодателям. Можно включить любую запись сразу, поставить её следующей или слушать очередь подряд.

Если отключить автовоспроизведение очереди, текущая реплика доиграет, а следующую можно будет запустить вручную. Кнопка «Очистить всё» удаляет очередь и останавливает озвучку.

<img src="https://olegbuchnev.github.io/WowVoiceTalkingHead/images/quest-queue-controls.19bb71da7b8d0f54a55f59b42280280c0ec666b6b450b7fc2a48a2d8ee7a49d3.png" alt="Очередь озвучки и управление воспроизведением" width="500">

## Источники озвучки

* **[WowVoice](https://www.curseforge.com/wow/addons/wowvoice-classic)** — озвучка классических заданий: **3 669 основных описаний**.
* **[CatQuest](https://www.curseforge.com/wow/addons/catquest) + [CatQuest Voices](https://www.curseforge.com/wow/addons/catquest-voices)** — альтернативная озвучка и дополнительные задания Forever: **4 473 основных описания**.
* **[Wayfarer](https://www.curseforge.com/wow/addons/wayfarer-russian-voiceover)** — озвучка заданий Альянса, Орды и общих заданий: **3 790 основных описаний** в трёх модулях.

Указано количество только основных описаний заданий, без реплик выполнения, сдачи и дополнительных вариантов пола персонажа. Часть заданий озвучена в нескольких библиотеках.

Для Wayfarer включите основной аддон и квестовые голосовые модули. **Настоятельно рекомендуется установить все три модуля:**

* **[Wayfarer Voices - Alliance](https://www.curseforge.com/wow/addons/wayfarer-voices-alliance)**
* **[Wayfarer Voices - Horde](https://www.curseforge.com/wow/addons/wayfarer-voices-horde)**
* **[Wayfarer Voices - Shared Quests](https://www.curseforge.com/wow/addons/wayfarer-voices-shared-quests)**

Модуль Narrator для квестовой озвучки не нужен. Если часть квестовых модулей отсутствует, предупреждение на карточке Wayfarer перечислит их.

Используйте рейтинг сообщества по расе и полу, задайте личный порядок для отдельных сочетаний или один общий порядок библиотек в настройках. При равных оценках или их отсутствии используется ваш общий порядок. Недоступные библиотеки пропускаются без изменения сохранённого приоритета. Реплики без доступной записи пропускаются.

## Совместимость

Пока TalkingHead Ru включён, CatQuest и Wayfarer используются как библиотеки: автозапуск, квестовые кнопки и автоматические уведомления подавляются. Ручное чтение книг и лора мест остаётся доступным. Если снова включить лор мест, его значок или голоса мира CatQuest в настройках библиотеки, TalkingHead Ru запомнит этот выбор и больше не будет менять эту настройку, в том числе после перезапуска.

При отключении TalkingHead Ru восстанавливаются только настройки, которыми он ещё управляет; ваш явный выбор лора сохраняется. Стартовое сообщение содержит ссылки только на загруженные библиотеки озвучки.

Основной плеер WowVoice отключается автоматически, чтобы задания не звучали дважды. Его библиотека **WowVoiceSounds** остаётся включённой.

Кнопки повторного прослушивания поддерживают стандартный трекер, в том числе с оформлением EllesmereUI, и Questie Tracker. В собственных списках заданий других аддонов кнопки могут отсутствовать.

## Установка и настройки

1. Установите **TalkingHead Ru** для **WoW Forever**.
2. Установите **хотя бы одну библиотеку озвучки**: **WowVoice**, **CatQuest + CatQuest Voices** или **Wayfarer с квестовыми голосовыми модулями**. Для максимального охвата рекомендуется установить все три библиотеки. Для Wayfarer настоятельно рекомендуются все три квестовых модуля.
3. Полностью перезапустите игру и включите TalkingHead Ru и необходимые аддоны библиотек в списке модификаций.
4. Введите **`/thead`** или откройте **Параметры → Модификации → TalkingHead Ru**, чтобы перейти к настройкам.

В настройках можно задать приоритет библиотек озвучки, настроить автозапуск и очередь, изменить положение и масштаб говорящей головы.

После установки или обновления библиотек полностью перезапускайте игру, чтобы клиент увидел новые звуковые файлы.

На английском клиенте кнопки плеера отображаются на английском, настройки и каталог озвучки — на русском. При наличии текста задания в общей базе используется русский текст.

[Сайт и инструкция](https://olegbuchnev.github.io/WowVoiceTalkingHead/) · [Сообщить об ошибке](https://github.com/olegbuchnev/WowVoiceTalkingHead/issues)

***

## Help choose the best quest voices

Compare Russian voiceovers from **WowVoice, CatQuest, and Wayfarer**. Your votes will help us choose voices for quests and NPCs in **TalkingHead Ru**.

**[Compare voices →](https://talkingheadru.tw1.ru/)**

## Примите участие в выборе лучших голосов

Сравните озвучки **WowVoice, CatQuest и Wayfarer**. Ваши оценки помогут выбрать голоса для заданий и персонажей в **TalkingHead Ru**.

**[Сравнить голоса →](https://talkingheadru.tw1.ru/)**
