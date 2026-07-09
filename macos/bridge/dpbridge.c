/************************************************************************
 * dpbridge.c   Implementation of the C bridge between the dopewars      *
 *              engine and the native macOS (Swift/AppKit) UI.           *
 *                                                                      *
 * See dpbridge.h for the interface contract. This file may use glib     *
 * and the engine internals freely; none of that leaks into Swift.       *
 ************************************************************************/
#ifdef HAVE_CONFIG_H
#include <config.h>
#endif

#include <string.h>
#include <stdlib.h>
#include <glib.h>

#include "dopewars.h"
#include "message.h"
#include "serverside.h"
#include "convert.h"
#include "sound.h"
#include "tstring.h"
#include "mac_helpers.h"
#include "dpbridge.h"

/* The engine's client-side message hook. When set, the (in-process)
 * server delivers messages to us via this function pointer. */
extern void (*ClientMessageHandlerPt)(char *, Player *);

/* The player object representing "us" (the head of the client list). */
static Player *g_play = NULL;

/* Parsed command line held for the lifetime of the process. */
static struct CMDLINE *g_cmdline = NULL;

static DPEventCallback g_cb = NULL;
static void *g_cb_user = NULL;

/* State needed to interpret old/new fight messages, mirroring the
 * curses client's file-scope globals. */
static FightPoint g_fp;
static gboolean g_can_fire = FALSE, g_run_here = FALSE;

/* Last known fight opponent, tracked from decoded fight messages. */
static gchar *g_enemy_name = NULL;
static gchar *g_enemy_bitchname = NULL;
static int g_enemy_health = -1, g_enemy_bitches = -1;

static void dp_snapshot_difficulty_baseline(void);

static void reset_enemy(void)
{
  g_free(g_enemy_name); g_enemy_name = NULL;
  g_free(g_enemy_bitchname); g_enemy_bitchname = NULL;
  g_enemy_health = g_enemy_bitches = -1;
}

static void emit(DPEventKind kind, const char *s1, const char *s2)
{
  if (g_cb)
    g_cb(kind, s1, s2, g_cb_user);
}

/* ------------------------------------------------------------------ */
/* Message handling: the engine calls this for every server->client    */
/* message. We update the Player struct via HandleGenericClientMessage */
/* and then translate the remainder into structured UI events.         */
/* ------------------------------------------------------------------ */
static DispMode g_disp = DM_NONE;

static void bridge_handle_message(char *Message, Player *Play)
{
  char *pt, *Data, *wrd;
  AICode AI;
  MsgCode Code;
  Player *From;
  gboolean Handled;

  if (ProcessMessage(Message, Play, &From, &AI, &Code, &Data, FirstClient)
      == -1) {
    return;
  }

  Handled = HandleGenericClientMessage(From, AI, Code, Play, Data, &g_disp);

  switch (Code) {
  case C_ENDLIST:
    /* End of the initial player list; game is ready. */
    emit(DP_EV_UPDATE, NULL, NULL);
    break;
  case C_STARTHISCORE:
    emit(DP_EV_HISCORE_START, NULL, NULL);
    break;
  case C_HISCORE:
    {
      /* Format: "<index>^<B|N><formatted line>" (B = the player's own
       * score, shown emphasized). */
      gchar *hp = Data;
      (void)GetNextInt(&hp, 0);
      if (hp && strlen(hp) >= 2) {
        emit(DP_EV_HISCORE_LINE, hp + 1, hp[0] == 'B' ? "B" : "");
      }
    }
    break;
  case C_ENDHISCORE:
    emit(DP_EV_HISCORE_END, Data, NULL);
    if (strcmp(Data, "end") == 0)
      emit(DP_EV_GAMEOVER, NULL, NULL);
    break;
  case C_PRINTMESSAGE:
    emit(DP_EV_PRINT, Data, NULL);
    break;
  case C_FIGHTPRINT:
    {
      gchar *AttackName, *DefendName, *BitchName, *textpt;
      int DefendHealth, DefendBitches, BitchesKilled, ArmPercent;
      gboolean Loot;
      if (HaveAbility(Play, A_NEWFIGHT)) {
        ReceiveFightMessage(Data, &AttackName, &DefendName, &DefendHealth,
                            &DefendBitches, &BitchName, &BitchesKilled,
                            &ArmPercent, &g_fp, &g_run_here, &Loot,
                            &g_can_fire, &textpt);
        /* Track the opponent for the fight HUD. An empty name in the
         * message means "you"; a non-empty defender name comes with its
         * current health and escort count. */
        if (DefendName && DefendName[0]) {
          if (!g_enemy_name || strcmp(g_enemy_name, DefendName) != 0) {
            g_free(g_enemy_name);
            g_enemy_name = g_strdup(DefendName);
          }
          g_enemy_health = DefendHealth;
          g_enemy_bitches = DefendBitches;
          if (BitchName && BitchName[0]) {
            g_free(g_enemy_bitchname);
            g_enemy_bitchname = g_strdup(BitchName);
          }
        } else if (AttackName && AttackName[0] && !g_enemy_name) {
          g_enemy_name = g_strdup(AttackName);
        }
      } else {
        textpt = Data;
        g_fp = (Play->Flags & FIGHTING) ? F_MSG : F_LASTLEAVE;
        g_can_fire = (Play->Flags & CANSHOOT) ? TRUE : FALSE;
        g_run_here = FALSE;
      }
      emit(DP_EV_UPDATE, NULL, NULL);
      /* Always emit, even with empty text: the UI must refresh its fight
       * controls whenever fp / can-fire / run-here change. */
      emit(DP_EV_FIGHT, (textpt && textpt[0]) ? textpt : "", NULL);
    }
    break;
  case C_SUBWAYFLASH:
    {
      GSList *list;
      gchar *loc;
      /* Mirror the curses client: arriving somewhere ends any fight. */
      for (list = FirstClient; list; list = g_slist_next(list)) {
        Player *tmp = (Player *)list->data;
        tmp->Flags &= ~FIGHTING;
      }
      g_fp = 0;
      g_can_fire = g_run_here = FALSE;
      reset_enemy();
      SoundPlay(Sounds.Jet);
      loc = Location ? Location[Play->IsAt].Name : "";
      emit(DP_EV_SUBWAY, loc, NULL);
      emit(DP_EV_UPDATE, NULL, NULL);
    }
    break;
  case C_QUESTION:
    pt = Data;
    wrd = GetNextWord(&pt, "");
    /* str1 = allowed letters, str2 = prompt text */
    emit(DP_EV_QUESTION, wrd, pt);
    break;
  case C_LOANSHARK:
    emit(DP_EV_LOANSHARK, NULL, NULL);
    break;
  case C_BANK:
    emit(DP_EV_BANK, NULL, NULL);
    break;
  case C_GUNSHOP:
    emit(DP_EV_GUNSHOP, NULL, NULL);
    break;
  case C_MSG:
  case C_MSGTO:
  case C_JOIN:
  case C_LEAVE:
  case C_RENAME:
    /* Multiplayer chatter; single player rarely sees these. */
    if (Data && Data[0])
      emit(DP_EV_MESSAGE, Data, NULL);
    break;
  case C_UPDATE:
    if (From == &Noone) {
      ReceivePlayerData(Play, Data, Play);
      emit(DP_EV_UPDATE, NULL, NULL);
    }
    break;
  case C_DRUGHERE:
  case C_TRADE:
  case C_INIT:
  case C_DATA:
  case C_ABILITIES:
    /* Already applied to Play by HandleGenericClientMessage. */
    emit(DP_EV_UPDATE, NULL, NULL);
    break;
  default:
    (void)Handled;
    break;
  }
}

/* ------------------------------------------------------------------ */
/* Lifecycle                                                           */
/* ------------------------------------------------------------------ */

void dp_init(const char *resource_dir, const char *hiscore_path)
{
  static gboolean inited = FALSE;
  if (inited)
    return;
  inited = TRUE;

  WantUTF8Errors(FALSE);
  LocaleIsUTF8 = TRUE;

  /* GeneralStartup performs the engine's normal bootstrap (initializes the
   * privileged high-score path used later by InitConfiguration, seeds the
   * RNG, sets up Log/Noone, and parses the command line). We feed it a
   * single-argument argv so no CLI options are consumed. */
  {
    char prog[] = "dopewars";
    char *argv[] = { prog, NULL };
    g_cmdline = GeneralStartup(1, argv);
  }

  /* Redirect the high score file to the caller-supplied writable location. */
  if (hiscore_path && hiscore_path[0]) {
    g_free(g_cmdline->scorefile);
    g_cmdline->scorefile = g_strdup(hiscore_path);
  }
  g_cmdline->antique = WantAntique;

  /* Apply the built-in default configuration (and any overrides above). */
  InitConfiguration(g_cmdline);

  /* Point the sound effects at the WAVs bundled in the app's Resources
   * (the defaults reference the Unix install prefix, which doesn't exist
   * inside an app bundle). */
  if (resource_dir && resource_dir[0]) {
    struct { gchar **dest; const char *file; } snd[] = {
      { &Sounds.FightHit,         "colt.wav" },
      { &Sounds.FightReload,      "gun.wav" },
      { &Sounds.EnemyBitchKilled, "shotdown.wav" },
      { &Sounds.BitchKilled,      "losebitch.wav" },
      { &Sounds.EnemyKilled,      "shotdown.wav" },
      { &Sounds.Killed,           "die.wav" },
      { &Sounds.EnemyFlee,        "run.wav" },
      { &Sounds.Flee,             "run.wav" },
      { &Sounds.EnemyFailFlee,    "run.wav" },
      { &Sounds.FailFlee,         "run.wav" },
      { &Sounds.Jet,              "train.wav" },
      { &Sounds.TalkPrivate,      "murmur.wav" },
      { &Sounds.TalkToAll,        "message.wav" },
      { &Sounds.StartGame,        "jet.wav" },
      { &Sounds.EndGame,          "bye.wav" },
    };
    size_t si;
    for (si = 0; si < sizeof(snd) / sizeof(snd[0]); si++) {
      gchar *path = g_strdup_printf("%s/sounds/19.5degs/%s",
                                    resource_dir, snd[si].file);
      AssignName(snd[si].dest, path);
      g_free(path);
    }
  }

  /* Sets up the string converter used by the message layer. */
  InitNetwork();

  /* SoundInit only registers the available drivers; SoundOpen(NULL)
   * selects and opens the first one (the Cocoa driver). Without it the
   * engine's SoundPlay calls are silent no-ops. */
  SoundInit();
  SoundOpen(NULL);

  /* Record the configured police/cop stats as the "Normal" difficulty
   * baseline (see dp_set_difficulty). */
  dp_snapshot_difficulty_baseline();
}

void dp_set_callback(DPEventCallback cb, void *user)
{
  g_cb = cb;
  g_cb_user = user;
}

void dp_set_hiscore_path(const char *path)
{
  if (!path || !path[0] || !HiScoreFile) {
    return;                     /* dp_init not run yet */
  }
  if (strcmp(HiScoreFile, path) == 0) {
    return;                     /* already on this board */
  }
  CloseHighScoreFile();
  AssignName(&HiScoreFile, (gchar *)path);
  OpenHighScoreFile();
}

/* dp_set_antique is defined below the baseline snapshot it relies on. */

void dp_set_game_rules(const DPGameRules *rules)
{
  NumTurns = rules->num_turns;
  StartCash = rules->start_cash;
  StartDebt = rules->start_debt;
  Sanitized = rules->sanitized ? TRUE : FALSE;
  DebtInterest = rules->debt_interest;
  BankInterest = rules->bank_interest;
  Drugs.CheapDivide = rules->cheap_divide;
  Drugs.ExpensiveMultiply = rules->expensive_multiply;
  PlayerArmor = rules->player_armor;
  BitchArmor = rules->bitch_armor;
  Bitch.MinPrice = rules->bitch_min_price;
  Bitch.MaxPrice = rules->bitch_max_price;
  Prices.Spy = rules->spy_price;
  Prices.Tipoff = rules->tipoff_price;
  StartDate.day = rules->start_day;
  StartDate.month = rules->start_month;
  StartDate.year = rules->start_year;
}

/* Baselines for the difficulty preset and for antique-mode toggling,
 * snapshotted after dp_init has applied the configuration (so user
 * config files are respected). */
static int *g_base_police = NULL;
static struct {
  int attack, defend, mindep, maxdep;
} *g_base_cop = NULL;
static int g_base_nloc = 0, g_base_ncop = 0;
static struct LOCATION *g_base_loc = NULL;
static int g_base_gunshop = 0, g_base_roughpub = 0;

static void dp_snapshot_difficulty_baseline(void)
{
  int i;

  g_base_nloc = NumLocation;
  g_base_police = g_new(int, g_base_nloc);
  g_base_loc = g_new0(struct LOCATION, g_base_nloc);
  for (i = 0; i < g_base_nloc; i++) {
    g_base_police[i] = Location[i].PolicePresence;
    CopyLocation(&g_base_loc[i], &Location[i]);
  }
  g_base_gunshop = GunShopLoc;
  g_base_roughpub = RoughPubLoc;
  g_base_ncop = NumCop;
  g_base_cop = g_malloc(g_base_ncop * sizeof(*g_base_cop));
  for (i = 0; i < g_base_ncop; i++) {
    g_base_cop[i].attack = Cop[i].AttackPenalty;
    g_base_cop[i].defend = Cop[i].DefendPenalty;
    g_base_cop[i].mindep = Cop[i].MinDeputies;
    g_base_cop[i].maxdep = Cop[i].MaxDeputies;
  }
}

void dp_set_antique(bool antique)
{
  int i;

  WantAntique = antique ? TRUE : FALSE;
  if (!g_base_loc) {
    return;                     /* dp_init not run yet */
  }
  /* Mirror SetupParameters()'s antique branch: the original game has no
   * gun shop and no pub (so no escort hiring), and only the first six
   * locations. Restore the configured world when antique is off. */
  if (antique) {
    GunShopLoc = RoughPubLoc = 0;
    if (g_base_nloc >= 6 && NumLocation != 6) {
      ResizeLocations(6);
      for (i = 0; i < 6; i++) {
        CopyLocation(&Location[i], &g_base_loc[i]);
      }
    }
  } else {
    GunShopLoc = g_base_gunshop;
    RoughPubLoc = g_base_roughpub;
    if (NumLocation != g_base_nloc) {
      ResizeLocations(g_base_nloc);
    }
    for (i = 0; i < g_base_nloc; i++) {
      CopyLocation(&Location[i], &g_base_loc[i]);
    }
  }
}

static int dp_clampi(int v, int lo, int hi)
{
  return v < lo ? lo : (v > hi ? hi : v);
}

void dp_set_difficulty(DPDifficulty level)
{
  int i;

  if (!g_base_police || !g_base_cop) {
    return;                     /* dp_init not run yet */
  }

  /* Always restore the baseline first so presets never compound. */
  for (i = 0; i < g_base_nloc && i < NumLocation; i++) {
    Location[i].PolicePresence = g_base_police[i];
  }
  for (i = 0; i < g_base_ncop && i < NumCop; i++) {
    Cop[i].AttackPenalty = g_base_cop[i].attack;
    Cop[i].DefendPenalty = g_base_cop[i].defend;
    Cop[i].MinDeputies = g_base_cop[i].mindep;
    Cop[i].MaxDeputies = g_base_cop[i].maxdep;
  }
  if (level == DP_DIFFICULTY_NORMAL) {
    return;
  }

  for (i = 0; i < g_base_nloc && i < NumLocation; i++) {
    if (level == DP_DIFFICULTY_EASY) {
      Location[i].PolicePresence = g_base_police[i] / 2;
    } else {
      Location[i].PolicePresence =
          dp_clampi(g_base_police[i] * 3 / 2, 0, 100);
    }
  }
  /* A larger attack/defend penalty makes cops worse shots (it is
   * subtracted from their combat rating in serverside.c). */
  for (i = 0; i < g_base_ncop && i < NumCop; i++) {
    if (level == DP_DIFFICULTY_EASY) {
      Cop[i].AttackPenalty = dp_clampi(g_base_cop[i].attack + 15, 0, 100);
      Cop[i].DefendPenalty = dp_clampi(g_base_cop[i].defend + 15, 0, 100);
      Cop[i].MaxDeputies = g_base_cop[i].maxdep / 2;
      Cop[i].MinDeputies = MIN(g_base_cop[i].mindep, Cop[i].MaxDeputies);
    } else {
      Cop[i].AttackPenalty = dp_clampi(g_base_cop[i].attack - 10, 0, 100);
      Cop[i].DefendPenalty = dp_clampi(g_base_cop[i].defend - 10, 0, 100);
      Cop[i].MinDeputies = g_base_cop[i].mindep * 2;
      Cop[i].MaxDeputies = g_base_cop[i].maxdep * 2;
    }
  }
}

void dp_set_family_friendly_names(bool family_friendly)
{
  AssignName(&Names.Bitch, (gchar *)(family_friendly ? "escort" : "bitch"));
  AssignName(&Names.Bitches,
             (gchar *)(family_friendly ? "escorts" : "bitches"));
}

void dp_set_currency(const char *symbol, bool prefix)
{
  AssignName(&Currency.Symbol,
             (gchar *)(symbol && symbol[0] ? symbol : "$"));
  Currency.Prefix = prefix ? TRUE : FALSE;
}

void dp_new_game(const char *player_name)
{
  /* Tear down any previous game/server state. */
  if (FirstServer) {
    CleanUpServer();
  }
  while (FirstClient) {
    FirstClient = RemovePlayer((Player *)FirstClient->data, FirstClient);
  }
  g_play = NULL;
  g_disp = DM_NONE;

  Server = Client = Network = FALSE;

  /* Create the single client player and make it the head of the list. */
  g_play = g_new0(Player, 1);
  FirstClient = AddPlayer(0, g_play, FirstClient);

  g_fp = 0;
  g_can_fire = g_run_here = FALSE;
  reset_enemy();

  ClientMessageHandlerPt = bridge_handle_message;

  /* Negotiate protocol abilities with the in-process server, exactly as
   * the curses client does: InitAbilities + SendAbilities BEFORE C_NAME,
   * so both sides agree on A_NEWFIGHT/A_DONEFIGHT etc. Without this the
   * server falls back to the legacy fight protocol. */
  InitAbilities(g_play);
  SendAbilities(g_play);
  SetPlayerName(g_play, (char *)player_name);

  SoundPlay(Sounds.StartGame);

  /* Kick off the game: this drives the in-process server to send initial
   * data, prices, and the first E_ARRIVE event back through our handler. */
  SendNullClientMessage(g_play, C_NONE, C_NAME, NULL, (char *)player_name);
}

/* ------------------------------------------------------------------ */
/* Read accessors                                                      */
/* ------------------------------------------------------------------ */

const char *dp_player_name(void)
{
  return g_play ? GetPlayerName(g_play) : "";
}
int64_t dp_cash(void)  { return g_play ? (int64_t)g_play->Cash : 0; }
int64_t dp_debt(void)  { return g_play ? (int64_t)g_play->Debt : 0; }
int64_t dp_bank(void)  { return g_play ? (int64_t)g_play->Bank : 0; }
int dp_health(void)    { return g_play ? g_play->Health : 0; }
int dp_bitches(void)   { return g_play ? g_play->Bitches.Carried : 0; }
int dp_location(void)  { return g_play ? g_play->IsAt : 0; }
int dp_turn(void)      { return g_play ? g_play->Turn : 0; }
int dp_num_turns(void) { return NumTurns; }

int dp_coat_used(void)
{
  int used = 0, i;
  if (!g_play)
    return 0;
  for (i = 0; i < NumDrug; i++)
    used += g_play->Drugs[i].Carried;
  for (i = 0; i < NumGun; i++)
    used += g_play->Guns[i].Carried * Gun[i].Space;
  return used;
}

/* The engine's CoatSize field is the REMAINING free space (buys subtract
 * from it), so free space comes straight from the player, and capacity
 * is free + used. */
int dp_space_free(void)
{
  return g_play ? g_play->CoatSize : 0;
}

int dp_coat_size(void)
{
  return dp_space_free() + dp_coat_used();
}

char *dp_date_string(void)
{
  GString *s = g_string_new("");
  char *out;
  if (g_play)
    GetDateString(s, g_play);
  out = g_strdup(s->str);
  g_string_free(s, TRUE);
  return out;
}

int dp_num_locations(void) { return NumLocation; }
const char *dp_location_name(int i)
{
  return (i >= 0 && i < NumLocation) ? Location[i].Name : "";
}

int dp_num_drugs(void) { return NumDrug; }
const char *dp_drug_name(int i)
{
  return (i >= 0 && i < NumDrug) ? Drug[i].Name : "";
}
int64_t dp_drug_price(int i)
{
  return (g_play && i >= 0 && i < NumDrug) ? (int64_t)g_play->Drugs[i].Price : 0;
}
int dp_drug_carried(int i)
{
  return (g_play && i >= 0 && i < NumDrug) ? g_play->Drugs[i].Carried : 0;
}
int64_t dp_drug_min_price(int i)
{
  return (i >= 0 && i < NumDrug) ? (int64_t)Drug[i].MinPrice : 0;
}
int64_t dp_drug_max_price(int i)
{
  return (i >= 0 && i < NumDrug) ? (int64_t)Drug[i].MaxPrice : 0;
}
int64_t dp_drug_total_value(int i)
{
  return (g_play && i >= 0 && i < NumDrug)
      ? (int64_t)g_play->Drugs[i].TotalValue : 0;
}

int dp_num_guns(void) { return NumGun; }
const char *dp_gun_name(int i)
{
  return (i >= 0 && i < NumGun) ? Gun[i].Name : "";
}
int64_t dp_gun_price(int i)
{
  return (i >= 0 && i < NumGun) ? (int64_t)Gun[i].Price : 0;
}
int dp_gun_space(int i)
{
  return (i >= 0 && i < NumGun) ? Gun[i].Space : 0;
}
int dp_gun_carried(int i)
{
  return (g_play && i >= 0 && i < NumGun) ? g_play->Guns[i].Carried : 0;
}

const char *dp_name_drugs(void)   { return Names.Drugs ? Names.Drugs : "drugs"; }
const char *dp_name_guns(void)    { return Names.Guns ? Names.Guns : "guns"; }
const char *dp_name_bitches(void) { return Names.Bitches ? Names.Bitches : "bitches"; }
const char *dp_currency_symbol(void)
{
  return Currency.Symbol ? Currency.Symbol : "$";
}

char *dp_format_price(int64_t price)
{
  return FormatPrice((price_t)price);   /* already heap-allocated */
}
void dp_free_string(char *s) { g_free(s); }

bool dp_is_fighting(void) { return g_play && (g_play->Flags & FIGHTING); }
bool dp_can_shoot(void)   { return g_play && (g_play->Flags & CANSHOOT); }
bool dp_is_dead(void)     { return g_play && g_play->Health == 0; }

char dp_fight_point(void)        { return (char)g_fp; }
bool dp_fight_can_fire(void)     { return g_can_fire ? true : false; }
bool dp_fight_can_run_here(void) { return g_run_here ? true : false; }
int dp_total_guns(void)
{
  return g_play ? TotalGunsCarried(g_play) : 0;
}
bool dp_is_antique(void) { return WantAntique ? true : false; }

const char *dp_fight_enemy_name(void)
{
  return g_enemy_name ? g_enemy_name : "";
}
int dp_fight_enemy_health(void)  { return g_enemy_health; }
int dp_fight_enemy_bitches(void) { return g_enemy_bitches; }
const char *dp_fight_enemy_bitch_name(void)
{
  return g_enemy_bitchname ? g_enemy_bitchname : "";
}

/* ------------------------------------------------------------------ */
/* Actions                                                             */
/* ------------------------------------------------------------------ */

void dp_jet(int location_index)
{
  char buf[32];
  if (!g_play)
    return;
  g_snprintf(buf, sizeof(buf), "%d", location_index);
  g_disp = DM_NONE;
  SendClientMessage(g_play, C_NONE, C_REQUESTJET, NULL, buf);
}

void dp_buy_drug(int drug_index, int amount)
{
  char *text;
  if (!g_play)
    return;
  text = g_strdup_printf("drug^%d^%d", drug_index, amount);
  SendClientMessage(g_play, C_NONE, C_BUYOBJECT, NULL, text);
  g_free(text);
}

void dp_buy_gun(int gun_index, int amount)
{
  char *text;
  if (!g_play)
    return;
  text = g_strdup_printf("gun^%d^%d", gun_index, amount);
  SendClientMessage(g_play, C_NONE, C_BUYOBJECT, NULL, text);
  g_free(text);
}

void dp_pay_loan(int64_t amount)
{
  char *prstr;
  if (!g_play)
    return;
  prstr = pricetostr((price_t)amount);
  SendClientMessage(g_play, C_NONE, C_PAYLOAN, NULL, prstr);
  g_free(prstr);
}

void dp_bank_deposit(int64_t amount)
{
  char *prstr;
  if (!g_play)
    return;
  prstr = pricetostr((price_t)amount);
  SendClientMessage(g_play, C_NONE, C_DEPOSIT, NULL, prstr);
  g_free(prstr);
}

void dp_answer(const char *letter)
{
  if (!g_play)
    return;
  SendClientMessage(g_play, C_NONE, C_ANSWER, NULL, (char *)letter);
}

void dp_done(void)
{
  if (!g_play)
    return;
  SendClientMessage(g_play, C_NONE, C_DONE, NULL, NULL);
}

/* The fight actions mirror the curses client's DM_FIGHT key handling
 * exactly (curses_client.c, 'F'/'S'/'R'/'D' cases). */

void dp_fight_shoot(void)
{
  if (!g_play || !g_can_fire || TotalGunsCarried(g_play) == 0)
    return;
  g_play->Flags &= ~CANSHOOT;
  g_can_fire = FALSE;
  SendClientMessage(g_play, C_NONE, C_FIGHTACT, NULL, "F");
}

void dp_fight_stand(void)
{
  if (!g_play || !g_can_fire || TotalGunsCarried(g_play) > 0)
    return;
  g_play->Flags &= ~CANSHOOT;
  g_can_fire = FALSE;
  SendClientMessage(g_play, C_NONE, C_FIGHTACT, NULL, "S");
}

void dp_fight_run(void)
{
  if (!g_play || !g_run_here)
    return;
  SendClientMessage(g_play, C_NONE, C_FIGHTACT, NULL, "R");
}

void dp_fight_finish(void)
{
  if (!g_play)
    return;
  /* "Deal drugs": leave the fight display. If the fight is really over,
   * acknowledge it so the server resumes the interrupted event chain. */
  if (!(g_play->Flags & FIGHTING) && HaveAbility(g_play, A_DONEFIGHT)) {
    SendClientMessage(g_play, C_NONE, C_DONE, NULL, NULL);
  }
  g_fp = 0;
  g_can_fire = g_run_here = FALSE;
  reset_enemy();
}

void dp_request_score(void)
{
  if (!g_play)
    return;
  SendClientMessage(g_play, C_NONE, C_REQUESTSCORE, NULL, NULL);
}

void dp_want_quit(void)
{
  if (!g_play)
    return;
  SendClientMessage(g_play, C_NONE, C_WANTQUIT, NULL, NULL);
}

void dp_open_url(const char *url)
{
#ifdef HAVE_COCOA
  mac_open_url(url);
#else
  (void)url;
#endif
}

void dp_set_sound_enabled(bool enabled)
{
  SoundEnable(enabled ? TRUE : FALSE);
}

bool dp_sound_enabled(void)
{
  return IsSoundEnabled() ? true : false;
}
