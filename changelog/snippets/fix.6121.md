- (#6121) Fix UEF SACU fire rate upgrade using inaccurate fire rate value.
  
  The upgrade displayed 1.82x fire rate, but in fact provided 2x fire rate because of how fire rate is rounded to game ticks.