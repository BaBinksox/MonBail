#!/bin/bash
# Lance toutes les simulations et affiche leur verdict final.
# Usage : tools/sim/run_all.sh        (voir tools/README.md pour les prérequis)
cd "$(dirname "$0")"
status=0
for test in boot_test creator_test quest_test multiplayer_test client_test powers_test placement_test daynight_test audio_test race_test arrival_test movement_test combat_test; do
	output=$(./run.sh "$test" 2>&1)
	verdict=$(echo "$output" | tail -1)
	failures=$(echo "$output" | grep -c "ÉCHEC")
	printf "%-18s %s\n" "$test" "$verdict"
	if [ "$failures" -gt 0 ]; then
		echo "$output" | grep "ÉCHEC\|ERREUR" | head -10
		status=1
	fi
done
exit $status
