/************************************************************************
 * dpbridge.h   C bridge between the dopewars engine and the native     *
 *              macOS (Swift/AppKit) user interface.                    *
 *                                                                      *
 * The dopewars engine is built as a single-player, in-process          *
 * client+server (no networking). This bridge:                          *
 *   - initializes the engine configuration,                            *
 *   - starts a single-player game,                                     *
 *   - registers a callback so server->client messages are decoded      *
 *     into structured events for the Swift UI,                         *
 *   - exposes read accessors for the current game state,               *
 *   - exposes action senders (jet, buy, sell, bank, loan, answer...).  *
 *                                                                      *
 * This file is intentionally free of glib types so it can be imported  *
 * cleanly by Swift via a module map.                                   *
 ************************************************************************/
#ifndef DP_BRIDGE_H
#define DP_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Event codes delivered to the UI callback ---------------------- */
typedef enum {
  DP_EV_UPDATE = 0,   /* Player state changed; UI should re-read state.   */
  DP_EV_MESSAGE,      /* A plain text message (str1).                     */
  DP_EV_QUESTION,     /* A yes/no-style question: str1=allowed letters,   */
                      /* str2=prompt text. Answer with dp_answer().       */
  DP_EV_PRINT,        /* Server "print message" (str1). Modal-ish note.   */
  DP_EV_LOANSHARK,    /* Entered the loan shark. Finish with dp_done().   */
  DP_EV_BANK,         /* Entered the bank. Finish with dp_done().         */
  DP_EV_GUNSHOP,      /* Entered the gun shop. Finish with dp_done().     */
  DP_EV_FIGHT,        /* A fight message (str1 = human-readable line).    */
  DP_EV_SUBWAY,       /* Arrived at a new location (str1 = location).     */
  DP_EV_HISCORE_START,/* High score table follows.                        */
  DP_EV_HISCORE_LINE, /* One high score line: str1 = formatted text,      */
                      /* str2 = "B" if it is the player's own score.      */
  DP_EV_HISCORE_END,  /* End of high score table. str1="end" => game over.*/
  DP_EV_GAMEOVER      /* The game has finished.                           */
} DPEventKind;

/* Callback invoked (on the main thread) for every UI-relevant event.
 * str1/str2 are UTF-8, valid only for the duration of the call. */
typedef void (*DPEventCallback)(DPEventKind kind, const char *str1,
                                const char *str2, void *user);

/* ---- Lifecycle ----------------------------------------------------- */

/* Initialize the engine configuration. Pass the app bundle resource
 * directory (for docs/sounds) and a writable path for the high score
 * file, or NULL to use defaults. Call once at startup. */
void dp_init(const char *resource_dir, const char *hiscore_path);

/* Register the UI event callback and its opaque user pointer. */
void dp_set_callback(DPEventCallback cb, void *user);

/* Start a fresh single-player game for a player with the given name. */
void dp_new_game(const char *player_name);

/* Enable "antique" (original Drug Wars) mode for the next new game. */
void dp_set_antique(bool antique);

/* Game-rule overrides, applied to the NEXT new game. Engine defaults
 * are given in the comments; num_turns of 0 means the game never ends,
 * and sanitized tones down random events. */
typedef struct {
  int     num_turns;           /* 31 */
  int64_t start_cash;          /* 2000 */
  int64_t start_debt;          /* 5500 */
  bool    sanitized;           /* false */
  int     debt_interest;       /* 10 (% per day on loan shark debt) */
  int     bank_interest;       /* 5  (% per day on bank balance) */
  int     cheap_divide;        /* 4  (price divider on "cheap" events) */
  int     expensive_multiply;  /* 4  (price multiplier on "spike" events) */
  int     player_armor;        /* 100 (% gunshot resistance) */
  int     bitch_armor;         /* 50  (% gunshot resistance of escorts) */
  int64_t bitch_min_price;     /* 50000  (escort hire price range) */
  int64_t bitch_max_price;     /* 150000 */
  int64_t spy_price;           /* 20000 (escort spy-on-enemy cost) */
  int64_t tipoff_price;        /* 10000 (escort cop-tipoff cost) */
  int     start_day;           /* 1    (in-game calendar start date) */
  int     start_month;         /* 12 */
  int     start_year;          /* 1984 */
} DPGameRules;

/* Callers must fill in EVERY field (start from the defaults above). */
void dp_set_game_rules(const DPGameRules *rules);

/* Difficulty preset: scales the per-location police presence and the
 * per-cop combat stats from their configured baselines (snapshotted at
 * dp_init). Applies to encounters from that point on; set before a new
 * game. Normal restores the baselines exactly. */
typedef enum {
  DP_DIFFICULTY_EASY = 0,
  DP_DIFFICULTY_NORMAL = 1,
  DP_DIFFICULTY_HARD = 2
} DPDifficulty;

void dp_set_difficulty(DPDifficulty level);

/* If enabled, engine-generated messages say "escort(s)" instead of the
 * original "bitch(es)" wording, matching the app's UI terminology. */
void dp_set_family_friendly_names(bool family_friendly);

/* Currency used when formatting prices: the symbol (e.g. "$") and
 * whether it precedes the amount. A NULL/empty symbol restores "$".
 * Cosmetic only — applies to all prices formatted from now on. */
void dp_set_currency(const char *symbol, bool prefix);

/* ---- Read accessors (current player / world) ----------------------- */

const char *dp_player_name(void);
int64_t dp_cash(void);
int64_t dp_debt(void);
int64_t dp_bank(void);
int      dp_health(void);
/* NOTE: the engine's Player.CoatSize field counts REMAINING free space,
 * not capacity. These accessors present both views consistently. */
int      dp_coat_size(void);       /* total coat capacity */
int      dp_coat_used(void);       /* space currently used */
int      dp_space_free(void);      /* space still available */
int      dp_bitches(void);
int      dp_location(void);        /* current location index */
int      dp_turn(void);
int      dp_num_turns(void);       /* 0 = unlimited */
/* Formatted current date string (e.g. "3rd August 1984"); caller must
 * free with dp_free_string(). */
char    *dp_date_string(void);

int          dp_num_locations(void);
const char  *dp_location_name(int i);

int          dp_num_drugs(void);
const char  *dp_drug_name(int i);
int64_t      dp_drug_price(int i);   /* price here; 0 => not available */
int          dp_drug_carried(int i);
/* Normal price range from the game config. A current price below the
 * minimum means a "cheap" event; above the maximum means a price spike. */
int64_t      dp_drug_min_price(int i);
int64_t      dp_drug_max_price(int i);
/* Total amount paid for the currently carried units (0 if unknown). */
int64_t      dp_drug_total_value(int i);

int          dp_num_guns(void);
const char  *dp_gun_name(int i);
int64_t      dp_gun_price(int i);
int          dp_gun_space(int i);
int          dp_gun_carried(int i);

/* Names configured for flavour text. */
const char *dp_name_drugs(void);
const char *dp_name_guns(void);
const char *dp_name_bitches(void);
const char *dp_currency_symbol(void);

/* Format a price using the game's currency settings. Free with
 * dp_free_string(). */
char *dp_format_price(int64_t price);
void  dp_free_string(char *s);

/* Is the player currently in a fight / can they shoot? */
bool dp_is_fighting(void);
bool dp_can_shoot(void);
bool dp_is_dead(void);

/* ---- Fight state (valid after a DP_EV_FIGHT event) ------------------ */

/* The last FightPoint received: 'A' arrived, 'S' stand, 'H' hit,
 * 'M' miss, 'R' reload, 'L' leave, 'D' fight over (last leave),
 * 'F' failed flee, 'G' message; 0 if no fight message seen yet. */
char dp_fight_point(void);
/* TRUE if the player may act (fire/stand) right now. */
bool dp_fight_can_fire(void);
/* TRUE if the player can run without leaving the current location
 * (use dp_fight_run); otherwise fleeing requires a jet (dp_jet). */
bool dp_fight_can_run_here(void);
/* Total number of guns the player carries. */
int dp_total_guns(void);
/* Antique ("original Drug Wars") mode active? */
bool dp_is_antique(void);

/* Last known fight opponent (empty name if none). Health/bitches are the
 * most recent values reported by the server ( -1 if not yet known). */
const char *dp_fight_enemy_name(void);
int dp_fight_enemy_health(void);
int dp_fight_enemy_bitches(void);          /* deputies/bodyguards left */
const char *dp_fight_enemy_bitch_name(void);

/* ---- Actions (client -> server) ------------------------------------ */

void dp_jet(int location_index);        /* travel to a location */
void dp_buy_drug(int drug_index, int amount);   /* amount<0 => sell/drop */
void dp_buy_gun(int gun_index, int amount);      /* amount<0 => sell */
void dp_pay_loan(int64_t amount);
void dp_bank_deposit(int64_t amount);   /* amount<0 => withdraw */
void dp_answer(const char *letter);     /* reply to DP_EV_QUESTION */
void dp_done(void);                     /* leave bank/loan/gunshop */
void dp_fight_shoot(void);              /* fire (needs guns + can-fire)  */
void dp_fight_stand(void);              /* stand (no guns + can-fire)    */
void dp_fight_run(void);                /* run, staying here (can-run)   */
void dp_fight_finish(void);             /* "deal drugs": acknowledge the
                                         * end of a fight and resume     */
void dp_request_score(void);            /* show high score table */
void dp_want_quit(void);                /* quit / end the current game */

/* Open a URL in the system browser (About/help links). */
void dp_open_url(const char *url);

/* Enable/disable sound effects. */
void dp_set_sound_enabled(bool enabled);
bool dp_sound_enabled(void);

#ifdef __cplusplus
}
#endif

#endif /* DP_BRIDGE_H */
