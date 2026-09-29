// Generate model file ID -> camera family mappings from the WoW community listfile.
// Usage: node tools/build-camera-models.js <community-listfile.csv>
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const source = 'https://github.com/wowdev/wow-listfile/releases/tag/202609242243';
const rules = [
    // Classify orcs and tauren before broader patterns; specialize models below.
    ['orc', /^(?:orc(?!a)|felorc(?!netherdrake)|magharorc)/],
    ['tauren', /^(?:tauren|highmountaintauren|taunka)/],
    ['human', /^(?:human|kul[t]?iran|vrykul)/],
    ['dwarf', /^(?:dwarf|darkirondwarf|earthen)/],
    ['gnome', /^(?:gnome|mechagnome|lepergnome)/],
    ['construct', /^(?:goblinshredder)/],
    ['goblin', /^(?:goblin(?:$|male|female|_male|_female)|hobgoblin|gilgoblin)/],
    ['troll', /^(?:troll|foresttroll|icetroll|zandalaritroll|zandalari)/],
    ['elf', /^(?:nightelf|bloodelf|highelf|voidelf|nightborne)/],
    ['undead', /^(?:scourge|undead|skeleton|northrendskeleton|forsaken|ghoul|lich|abomination)/],
    ['draenei', /^(?:draenei|lightforgeddraenei|broken|lostone)/],
    ['worgen', /^(?:worgen)/],
    ['pandaren', /^(?:pandaren)/],
    ['vulpera', /^(?:vulpera)/],
    ['dracthyr', /^(?:dracthyr)/],
    ['ogre', /^(?:ogre|ogron|gronn)/],
    ['giant', /^(?:giant|mountaingiant|seagiant|frostgiant|stonegiant|stormgiant)/],
    ['furbolg', /^(?:furbolg)/],
    ['gnoll', /^(?:gnoll)/],
    ['murloc', /^(?:murloc|gorloc|jinyu|ankoan)/],
    ['kobold', /^(?:kobold|snobold)/],
    ['quillboar', /^(?:quillboar|quilboar)/],
    ['trogg', /^(?:trogg|troglodyte)/],
    ['sporeling', /^(?:sporeling|fungal|fungiant|fungalgiant)/],
    ['serpent', /^(?:sethrak|saurok)/],
    ['tortollan', /^(?:tortollan)/],
    ['hozen', /^(?:hozen|monkey)/],
    ['drogbar', /^(?:drogbar)/],
    ['niffen', /^(?:niffen)/],
    ['centaur', /^(?:centaur)/],
    ['dryad', /^(?:dryad|keeperofthegrove|keepergrove)/],
    ['naga', /^(?:naga)/],
    ['satyr', /^(?:satyr)/],
    ['harpy', /^(?:harpy)/],
    ['dragonkin', /^(?:dragonspawn|drakonid|drakonoid)/],
    ['dragon', /^(?:dragon|drake|whelp|faeriedragon|netherdragon|netherdrake|felorcnetherdrake)/],
    ['treant', /^(?:treant|ent$|ancientof|ancientprotector)/],
    ['elemental', /^(?:elemental|airelemental|waterelemental|fireelemental|earthelemental|stormelemental|firelord|infern(al|us))/],
    ['demon', /^(?:demon|dreadlord|doomguard|eredar|felguard|felhunter|felbeast|imp$|impoutland|succubus|incubus|pitlord|voidwalker)/],
    ['ethereal', /^(?:ethereal)/],
    ['tuskarr', /^(?:tuskarr|tuskar)/],
    ['arrakoa', /^(?:arakkoa|arrakoa)/],
    ['tolvir', /^(?:tolvir)/],
    ['construct', /^(?:golem|harvestgolem|mechastrider|clockwork|robot|mechanical|arcanegolem)/],
    ['quadruped', /^(?:bear|wolf|direwolf|worg$|worg\d|tiger|panther|cat$|lion|leopard|saber|raptor|boar|deer|stag|horse|kodo|clefthoof|elekk|fox|hyena|basilisk|crocolisk|turtle|gorilla|yeti|owlbeast)/],
    ['bird', /^(?:bird|owl$|owl\d|raven|crow$|eagle|hawk|strider|tallstrider|gryphon|hippogryph|wyvern)/],
    ['aquatic', /^(?:fish|shark|whale|dolphin|orca|seal|walrus|thresher|seaturtle|sealion)/],
    ['insect', /^(?:spider|silithid|nerubian|qiraj|aqir|mantid|scarab|scorpid|crab|lobster)/],
];
async function main() {
    if (!process.argv[2]) throw new Error('Provide a community-listfile.csv path');
    const entries = new Map();
    const input = readline.createInterface({input: fs.createReadStream(process.argv[2]), crlfDelay: Infinity});
    for await (const line of input) {
        const match = /^(\d+);((?:character|creature)\/([^/]+)\/.*\.m2)$/i.exec(line);
        if (!match) continue;
        const folder = match[3].toLowerCase();
        const rule = match[2].toLowerCase().endsWith('/goblinshredder.m2')
            ? ['construct'] : rules.find(([,pattern]) => pattern.test(folder));
        if (rule) {
            const filename = match[2].toLowerCase();
            // Female troll models do not need the male model's lateral correction.
            const femaleTroll = rule[0] === 'troll' && /female|priestess|(?:guard|caster)_f/.test(filename);
            // Keep the wide female blood elf talk animation separate from other elves.
            const femaleBloodElf = filename.startsWith('character/bloodelf/female/');
            const maleNightElf = filename.startsWith('character/nightelf/male/');
            const femaleNightElf = filename.startsWith('character/nightelf/female/');
            const maleHuman = filename.startsWith('character/human/male/');
            const femaleHuman = filename.startsWith('character/human/female/');
            const humanChild = /^creature\/human(?:male|female)kid[^/]*\//.test(filename);
            const maleGoblin = filename.startsWith('character/goblin/male/')
                || filename === 'creature/goblin/goblin.m2';
            const femaleOrc = filename.startsWith('character/orc/female/');
            const femaleTauren = filename.startsWith('character/tauren/female/');
            const femaleUndead = filename.startsWith('character/scourge/female/');
            const maleUndead = filename.startsWith('character/scourge/male/');
            const family = femaleOrc ? 'orc_female' : maleGoblin ? 'goblin_male' : femaleBloodElf ? 'bloodelf_female'
                : femaleTauren ? 'tauren_female' : femaleUndead ? 'undead_female'
                : maleUndead ? 'undead_male' : maleNightElf ? 'nightelf_male'
                : femaleNightElf ? 'nightelf_female'
                : maleHuman ? 'human_male' : femaleHuman ? 'human_female' : humanChild ? 'human_child'
                : femaleTroll ? 'troll_female' : rule[0];
            entries.set(Number(match[1]), {family, filename});
        }
    }
    if (entries.size < 100) throw new Error('Listfile did not contain the expected model mappings');
    const lines = ['-- Generated by tools/build-camera-models.js; do not edit manually.',
        '-- Model identities only; these are not Blizzard camera settings.', '-- Source: ' + source,
        'WowVoice.CameraModelProfiles = {'];
    for (const [id, entry] of [...entries].sort((a,b) => a[0]-b[0])) {
        lines.push(`    [${id}] = "${entry.family}", -- ${entry.filename}`);
    }
    lines.push('}', '');
    fs.writeFileSync(path.join(__dirname, '../src/CameraModels.lua'), lines.join('\n'));
    const counts = {};
    for (const {family} of entries.values()) counts[family]=(counts[family] || 0)+1;
    console.log(JSON.stringify({models: entries.size, families: counts}, null, 2));
}
main().catch(error => {console.error(error.message); process.exitCode=1;});
