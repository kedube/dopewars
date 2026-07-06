/* Headless smoke test: start a single-player game via the bridge, print
 * the initial state, do a couple of actions, and confirm the engine
 * responds. Not part of the app; used only to de-risk the port. */
#include <stdio.h>
#include <string.h>
#include "dpbridge.h"

static int updates = 0;

static void on_event(DPEventKind kind, const char *s1, const char *s2, void *u)
{
  (void)u;
  switch (kind) {
  case DP_EV_UPDATE:   updates++; break;
  case DP_EV_MESSAGE:  printf("[MSG] %s\n", s1 ? s1 : ""); break;
  case DP_EV_PRINT:    printf("[PRINT] %s\n", s1 ? s1 : ""); break;
  case DP_EV_QUESTION: printf("[QUESTION allowed=%s] %s\n", s1, s2); break;
  case DP_EV_LOANSHARK: printf("[LOANSHARK]\n"); break;
  case DP_EV_BANK:     printf("[BANK]\n"); break;
  case DP_EV_GUNSHOP:  printf("[GUNSHOP]\n"); break;
  case DP_EV_SUBWAY:   printf("[SUBWAY -> %s]\n", s1); break;
  case DP_EV_FIGHT:    printf("[FIGHT] %s\n", s1); break;
  case DP_EV_GAMEOVER: printf("[GAMEOVER]\n"); break;
  default: break;
  }
}

static void dump(void)
{
  char *date = dp_date_string();
  char *cash = dp_format_price(dp_cash());
  char *debt = dp_format_price(dp_debt());
  printf("--- %s | %s | cash=%s debt=%s health=%d space=%d/%d loc=%s(%d) turn=%d/%d\n",
         dp_player_name(), date, cash, debt, dp_health(),
         dp_coat_used(), dp_coat_size(),
         dp_location_name(dp_location()), dp_location(),
         dp_turn(), dp_num_turns());
  dp_free_string(date); dp_free_string(cash); dp_free_string(debt);
}

int main(void)
{
  dp_init(NULL, "/tmp/dopewars_smoketest.sco");
  dp_set_callback(on_event, NULL);
  dp_new_game("Tester");

  printf("Locations: %d, Drugs: %d, Guns: %d\n",
         dp_num_locations(), dp_num_drugs(), dp_num_guns());
  dump();

  printf("Drug prices here:\n");
  for (int i = 0; i < dp_num_drugs(); i++) {
    long long p = dp_drug_price(i);
    if (p > 0) {
      char *ps = dp_format_price(p);
      printf("  %-12s %s\n", dp_drug_name(i), ps);
      dp_free_string(ps);
    }
  }

  /* Buy the first affordable available drug. */
  for (int i = 0; i < dp_num_drugs(); i++) {
    long long p = dp_drug_price(i);
    if (p > 0 && p <= dp_cash()) {
      int amt = (int)(dp_cash() / p);
      if (amt > 5) amt = 5;
      printf("Buying %d of %s\n", amt, dp_drug_name(i));
      dp_buy_drug(i, amt);
      break;
    }
  }
  dump();

  /* Jet somewhere else. */
  int dest = (dp_location() + 1) % dp_num_locations();
  printf("Jetting to %s\n", dp_location_name(dest));
  dp_jet(dest);
  dump();

  printf("Total UPDATE events: %d\n", updates);
  printf("SMOKETEST OK\n");
  return 0;
}
