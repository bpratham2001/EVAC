extensions [py]
breed [snakes snake]
breed [graveyard grave]
breed [apples apple]
breed [tails tail]
globals
[
  chr-range-min ;; used for initialisation of chromosomes
  chr-range-max ;; used for initialisation of chromosomes
  current-gen ;; the current running generation
  avg-fitness ;; average score of all snakes
  highest-avg-fitness ;; highest avg-fitness across all generations
  highest-individual-score ;; highest individual score across all generations
  chromosome-length ;; (number of sensor readings+1 * numHidden1) + (numHidden1 * numHidden2) + (numHidden2 * output)
  num-tails-running-average ;; used in calculating Total Length running average
  total-tails ;; used in calculating Total Length running average
  current-gen-score ;; used in deciding which snakes to revive in the event of an extinction
]

snakes-own
[
  chromosome ;; floats ranging from chr-range-min to chr-range-max at initialisation. Used as weights for MLP
  score ;; number of apples eaten
  gen ;; the generation the snake is from
  num-tails ;; length of tail (incremented when consuming apples)
  f3 ;; f3 fitness of the snake
  last-move ;; The last move made, shared by proximity when asked
  last-advice ;; last move made by other snake
]

graveyard-own ;; used for revival, in the event of an extinction
[
  chr ;; chromosome
  score-at-death ;; score
  generation ;; gen
  tail-count ;; num-tails
]


;;;;;;;;;;;;;;;;;;
;;; Python MLP ;;;
;;;;;;;;;;;;;;;;;;

to pyset
  py:setup py:python3
  ifelse move-sharing
  [py:set "inputs" 19]
  [py:set "inputs" 18]
  (py:run
    "import numpy as np"
    "print('Successfully loaded Py extension.')"
    "class MLP(object):"
    "    def __init__(self, numInput, numHidden1, numHidden2, numOutput):"
    "        self.fitness = 0"
    "        self.numInput = numInput + 1"
    "        self.numHidden1 = numHidden1"
    "        self.numHidden2 = numHidden2"
    "        self.numOutput = numOutput"
    "        self.w_i_h1 = np.random.randn(self.numHidden1, self.numInput)"
    "        self.w_h1_h2 = np.random.randn(self.numHidden2, self.numHidden1)"
    "        self.w_h2_o = np.random.randn(self.numOutput, self.numHidden2)"
    "        self.ReLU = lambda x : max(0,x)"
    "    def softmax(self, x):"
    "        e_x = np.exp(x - np.max(x))"
    "        return e_x / e_x.sum()"
    "    def feedForward(self, inputs):"
    "        inputsBias = inputs[:]"
    "        inputsBias.insert(len(inputs),1)"
    "        h1 = np.dot(self.w_i_h1, inputsBias)"
    "        h1 = [self.ReLU(x) for x in h1]"
    "        h2 = np.dot(self.w_h1_h2, h1)"
    "        h2 = [self.ReLU(x) for x in h2]"
    "        output = np.dot(self.w_h2_o, h2)"
    "        return self.softmax(output)"
    "    def setWeightsLinear(self, Wgenome):"
    "        numWeights_I_H1 = self.numHidden1 * self.numInput"
    "        numWeights_H1_H2 = self.numHidden2 * self.numHidden1"
    "        numWeights_H2_O = self.numOutput * self.numHidden2"
    "        self.w_i_h1 = np.array(Wgenome[:numWeights_I_H1])"
    "        self.w_i_h1 = self.w_i_h1.reshape((self.numHidden1, self.numInput))"
    "        self.w_h1_h2 = np.array(Wgenome[numWeights_I_H1:(numWeights_H1_H2+numWeights_I_H1)])"
    "        self.w_h1_h2 = self.w_h1_h2.reshape((self.numHidden2, self.numHidden1))"
    "        self.w_h2_o = np.array(Wgenome[(numWeights_H1_H2+numWeights_I_H1):])"
    "        self.w_h2_o = self.w_h2_o.reshape((self.numOutput, self.numHidden2))"
    "myNet = MLP(inputs, 12, 8, 4)"
    ; 6 sensors * 3 possible readings + 1 shared move, 12 hidden channels, 8 hidden channels, 4 directions
   )
end

;;;;;;;;;;;;;;;;;;;;;;;;
;;; Setup procedures ;;;
;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all
  reset-ticks
  set chr-range-min -1.0
  set chr-range-max 1.0
  set current-gen 0
  set num-tails-running-average 0
  set current-gen-score 0
  pyset
  ifelse move-sharing
  [set chromosome-length ((20 * 12) + (12 * 8) + (8 * 4))] ; 2 hidden layer of 12 channels, 8 channels
  [set chromosome-length ((19 * 12) + (12 * 8) + (8 * 4))]
  ;[set chromosome-length ((14 * 8) + (8 * 4))] ; 1 hidden layer of 8 channels
  ;[set chromosome-length ((13 * 8) + (8 * 4))]
  create-apples 1 [setup-apples]
  create-snakes population [setup-snakes]
end

to setup-apples
  set shape "circle"
  set color red
  setxy 0 0
  set heading random 360
  setxy random-pxcor random-pycor
  while [any? other turtles-here]
  [
    set heading random 360
    fd 1
  ]
end

to setup-snakes
  set gen current-gen
  set size 1
  set color yellow
  set heading 90 * (random 4)
  set score 0
  set last-move random 4
  set last-advice random 4
  set num-tails 0

  while [any? other turtles-here]
  [
    setxy random-pxcor random-pycor
  ]

  ifelse (gen = 0) ;or (not evolution)
  [
    setup-chromosomes
  ]
  [
    mutate-chromosomes
  ]
end

to setup-chromosomes
  let statesBlank n-values chromosome-length [chr-range-min + (random-float (chr-range-max - chr-range-min))]
  set chromosome statesBlank
end

to go
  if count snakes = 0
  [
    ifelse revival
    [
      ask graveyard with [score-at-death > (current-gen-score / population)] [revive chr score-at-death generation]
      show "extinction"
      ask apples [die]
      ask graveyard [die]
      if count snakes = 0
      [
        show "no suitable snakes to revive"
        stop
      ]
    ]
    [stop]
  ]
  if ticks < cycleTime
  [
    if random-float 1 < apple-spawn-probability [create-apples 1 [setup-apples]]
    tick-snakes
    tick
  ]
;; once we reach cycleTime ticks we move to the next generation
  if ticks = cycleTime
  [
    if current-gen = end-date [stop]
    endOfCycle
    reset-ticks
  ]
end

;;;;;;;;;;;;;;;;;;;;;
;;; GA procedures ;;;
;;;;;;;;;;;;;;;;;;;;;

to compute-f3
  set f3 0                       ; reset f3
  let i 0                        ; gene counter set to 0
  repeat length chromosome [     ; for each locus (aka position) on the chromosome...
  let gene item i chromosome     ; store the value of my i-th gene
    let same-gene-count 1        ; me and how many other turtles have the same allele?
                                 ; (i.e. same value in the same position on the chromosome)
    let tmp score                ; to sum up and average fitnesses
    ask other turtles with [breed = snakes and item i chromosome = gene] [
      set tmp tmp + score       ; score is the fitness of a relevant turle from the other ones
      set same-gene-count same-gene-count + 1
    ]
    set tmp ( tmp / same-gene-count ) ; essentially, computes f2 for that gene
    set i i + 1 ; increment the gene counter
    set f3 f3 + tmp
  ]
  set f3 (f3 / i)
end

to endOfCycle
  ask snakes [compute-f3]
  set total-tails (total-tails + (count tails))
  set num-tails-running-average (total-tails / ((current-gen + 1) * population))
  let sumFitness 0
  ask snakes [set sumFitness (sumFitness + score)]
  set avg-fitness (sumFitness / population)
  print "Average Fitness: "
  print avg-fitness
  if avg-fitness > highest-avg-fitness [set highest-avg-fitness avg-fitness]
  ;ifelse evolution
  hatchNextGeneration
  ;[ ;; used when testing populations without evolution
  ;  set current-gen (current-gen + 1)
  ;  ask tails [die]
  ;  ask snakes [die]
  ;  ask apples [die]
  ;  ask graveyard [die]
  ;  create-apples 1 [setup-apples]
  ;  create-snakes population [setup-snakes]
  ;]
end

to hatchNextGeneration

  let tempSet (snakes with [gen <= current-gen])

  set current-gen (current-gen + 1)
  set current-gen-score 0
  ask tempSet
  [
    if score > highest-individual-score [set highest-individual-score score]
    if avg-fitness = 0 [set score 1]
  ]

  if avg-fitness = 0 [ set avg-fitness 1]
  let breaker 0
  while[ count snakes < (population * 2)]
  [
    ifelse (breaker < (2 * (count snakes)) and extended-fitness)
    [
      ask tempSet
      [
        if count snakes < (population * 2)
        [
          ;ifelse f3 > avg-fitness
          ifelse (f3 / avg-fitness) > random-float 1 ;avg fit as benchmark, f3 instead of raw allows weaker ones a chance
          [
            hatch-snakes 1 [setup-snakes]
          ]
          [
            set breaker (breaker + 1)
          ]
        ]
      ]
    ]
    [
      show "No snakes had significantly high f3 fitness."
      ask tempSet
      [
        if count snakes < (population * 2)
        [
          if (score / avg-fitness) > random-float 1 ;if f3 fitness fails, default to regular
          [
            hatch-snakes 1 [setup-snakes]
          ]
        ]
      ]
    ]
  ]
  ask tempSet [die]
  ask snakes [set num-tails 0]
  ask tails [die]
  ask apples [die]
  ask graveyard [die]
  create-apples 1 [setup-apples]
  crossOvr
end

to mutate-chromosomes
  set chromosome mutate-chromosome
end

to-report mutate-chromosome
  let j 0
  let stateBlock chromosome
    while [j < (chromosome-length)]
    [
      if mutationChance > random-float 1
      [
        set stateBlock replace-item j stateBlock (chr-range-min + (random-float (chr-range-max - chr-range-min)))
      ]
    set j ( j + 1 )
    ]
  report stateBlock
end


to crossOvr
  if count snakes > 1
  [
    let tempSet (snakes with [gen = current-gen])

    while[crossover > random-float 1]
    [
      let newSet (n-of 2 tempSet)
      ;; pick a random number  and swap chromosome block at that point
      let slicePoint random (round (chromosome-length / 2))

      let agent1 one-of newSet

      ask agent1
      [
        let agent2 other newSet
        let slice sublist chromosome 0 slicePoint
        let slice1 sublist chromosome slicePoint (chromosome-length)

        ask agent2
        [
          let slice2 sublist chromosome 0 slicePoint
          let slice3 sublist chromosome slicePoint (chromosome-length)
          set chromosome join-lists slice2 slice1
          ask agent1
          [
            set chromosome join-lists slice slice3
          ]
        ]

      ]
    ]
  ]
end

to-report join-lists[list1 list2]
  let jMax length list2
  let j 0
    while [j < jMax]
    [
      set list1 lput (item j list2) list1
      set j ( j + 1 )
    ]
  report list1
end

;;;;;;;;;;;;;;;;;;;;;;;;
;;; Agent procedures ;;;
;;;;;;;;;;;;;;;;;;;;;;;;

to tick-snakes
  ask snakes
  [
    action
  ]
end

to action
  ;let eyes look
  ifelse move-sharing
  [
    if any? other snakes [set last-advice get-advice]
    py:set "inputs" (sentence look last-advice) ; 19 element list
  ]
  [py:set "inputs" look] ; 18 element list
  py:set "x" chromosome
  (py:run
    "myNet.setWeightsLinear(x)"
    "output = myNet.feedForward(inputs)"
    "decision = np.argmax(output, axis=0)"
  )
  let move py:runresult "decision"
  ifelse move = 0 [set heading 0] ; north
  [ ifelse move = 1 [ set heading 90 ] ; east
    [ ifelse move = 2 [ set heading 270 ] ; west
      [ ifelse move = 3 [ set heading 180 ] ; south
        [ ;; default case
  ]]]]

  set last-move move

  let aprevx xcor
  let aprevy ycor
  fd 1
  ifelse (count snakes-here > 1) or (count tails-here > 0)
  [
    ifelse num-tails > 0
    [kill-tail]
    [
      death chromosome score gen
    ]
    die
  ][
    if count apples-here > 0
    [
      set score (score + 1)
      ask apples-here [die]
      add-tail
      set num-tails (num-tails + 1)
    ]
  ]
  if num-tails > 0
  [
    ask one-of in-link-neighbors [update-tail aprevx aprevy]
  ]
end

to-report look
  let norths (sub-look "n" 1)
  let easts (sub-look "e" 1)
  let souths (sub-look "s" 1)
  let wests (sub-look "w" 1)
  let northwests (sub-look "nw" 1)
  let northeasts (sub-look "ne" 1)
  report (sentence norths easts souths wests northwests northeasts)
end

to-report sub-look [dir dst]
  ifelse dir = "nw"
  [
    ;north-west
    ifelse ([count apples-here] of patch-left-and-ahead 45 dst) > 0 [report [1 0 0]]
    [ifelse (([count snakes-here] of patch-left-and-ahead 45 dst) > 0) or (([count tails-here] of patch-left-and-ahead 45 dst) > 0) [report [0 1 0]]
    [report [0 0 1]]]
  ][
    if dir = "ne"
    [
      ;north-east
      ifelse ([count apples-here] of patch-right-and-ahead 45 dst) > 0 [report [1 0 0]]
      [ifelse (([count snakes-here] of patch-right-and-ahead 45 dst) > 0) or (([count tails-here] of patch-right-and-ahead 45 dst) > 0) [report [0 1 0]]
      [report [0 0 1]]]
    ]
  ]
  ifelse dir = "n"
  [
    ;north
    ifelse ([count apples-here] of patch-ahead dst) > 0 [report [1 0 0]]
    [ifelse (([count snakes-here] of patch-ahead dst) > 0) or (([count tails-here] of patch-ahead dst) > 0) [report [0 1 0]]
    [report [0 0 1]]]
  ][
    ifelse dir = "e"
    [
      ;east
      ifelse ([count apples-here] of patch-right-and-ahead 90 dst) > 0 [report [1 0 0]]
      [ifelse (([count snakes-here] of patch-right-and-ahead 90 dst) > 0) or (([count tails-here] of patch-right-and-ahead 90 dst) > 0) [report [0 1 0]]
      [report [0 0 1]]]
    ][
      ifelse dir = "s"
      [
        ;south
        ifelse ([count apples-here] of patch-right-and-ahead 180 dst) > 0 [report [1 0 0]]
        [ifelse (([count snakes-here] of patch-right-and-ahead 180 dst) > 0) or (([count tails-here] of patch-right-and-ahead 180 dst) > 0) [report [0 1 0]]
        [report [0 0 1]]]
      ][
        ;west
        ifelse ([count apples-here] of patch-left-and-ahead 90 dst) > 0 [report [1 0 0]]
        [ifelse (([count snakes-here] of patch-left-and-ahead 90 dst) > 0) or (([count tails-here] of patch-left-and-ahead 90 dst) > 0) [report [0 1 0]]
        [report [0 0 1]]]
      ]
    ]
  ]
end

to-report get-advice
  let nearest-snake min-one-of other snakes [distance myself]
  report [last-move] of nearest-snake
end


to add-tail
  ifelse any? in-link-neighbors [
    ask one-of in-link-neighbors [ add-tail ]
  ] [
    hatch-tails 1 [ create-link-to myself ]
  ]
end

to update-tail [x y]
  let prevx xcor
  let prevy ycor
  setxy x y
  if breed = tails
  [
    face one-of out-link-neighbors
  ]
  if any? in-link-neighbors
  [
    ask one-of in-link-neighbors [update-tail prevx prevy]
  ]
end

to kill-tail ; recursively kills all tails
  ifelse any? in-link-neighbors
  [
    ask one-of in-link-neighbors
    [
      kill-tail
      die
    ]
  ]
  [
    ifelse breed = snakes
    [
      death chromosome score gen
      die
    ]
    [die]
  ]
end

to death_old ;not in use
  hatch-graveyard 1 [create-link-to myself]
  ask one-of in-link-neighbors [
    set chr chromosome
    set score-at-death score
    set generation gen
  ]
  set current-gen-score (current-gen-score + score)
  die
end

to death [c s g]
  hatch-graveyard 1
  [
    set chr c
    set score-at-death s
    set generation g
    ;set color black
    set color [255 0 0 0]
  ]
  set current-gen-score (current-gen-score + s)
end

to revive [c s g]
  hatch-snakes 1 [
    set gen current-gen
    set size 1
    set color yellow
    set heading 90 * (random 4)
    set last-move random 4
    set last-advice random 4
    set chromosome c
    set score s
    set num-tails 0
    set gen g
  ]
  die
end
@#$#@#$#@
GRAPHICS-WINDOW
203
10
533
341
-1
-1
16.1
1
10
1
1
1
0
1
1
1
0
19
0
19
0
0
1
ticks
30.0

SLIDER
0
46
200
79
population
population
1
50
10.0
1
1
NIL
HORIZONTAL

BUTTON
4
10
67
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
71
10
134
43
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
281
345
386
390
Current Generation
current-gen
17
1
11

SLIDER
0
82
201
115
cycleTime
cycleTime
1000
10000
2000.0
1000
1
NIL
HORIZONTAL

SLIDER
0
152
200
185
mutationChance
mutationChance
0
1
0.2
0.01
1
NIL
HORIZONTAL

MONITOR
671
343
800
388
Highest Average Fitness
highest-avg-fitness
17
1
11

MONITOR
539
343
668
388
Highest Individual Score
highest-individual-score
17
1
11

SLIDER
0
188
200
221
apple-spawn-probability
apple-spawn-probability
0
1
0.01
0.001
1
NIL
HORIZONTAL

PLOT
538
190
835
340
Average Fitness
ticks
fitness
0.0
1000.0
0.0
5.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot avg-fitness"

MONITOR
204
345
279
390
Current Alive
count snakes
0
1
11

MONITOR
388
345
532
390
Total Length (num-tails)
count tails
17
1
11

PLOT
537
10
835
185
Total Length of All Tails
ticks
length
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count tails"

SLIDER
0
117
201
150
crossover
crossover
0.1
1
0.5
0.1
1
NIL
HORIZONTAL

SWITCH
0
223
150
256
extended-fitness
extended-fitness
0
1
-1000

SWITCH
0
258
112
291
move-sharing
move-sharing
0
1
-1000

MONITOR
0
330
181
375
Total Length Running Average
num-tails-running-average
17
1
11

SWITCH
112
258
202
291
revival
revival
1
1
-1000

SLIDER
0
293
201
326
end-date
end-date
50
10000
50.0
10
1
NIL
HORIZONTAL

@#$#@#$#@
# EVAC Question 2
## Model Requirements
1) NetLogo 6.x.x
2) Python3
3) NumPy
## Model Description
### High-Level Overview
- models the behaviour of several snakes in a wrapped environment (no walls).
- snakes grow a tail when consuming an apple
- snakes die upon collision with turtles that are not apples
- each snake has sensors, each sensor reports a 1 hot encoding list for a certain patch [contains apple, contains non-apple turtle, is empty patch]
- each snake has a chromosome, consisting of floats
- chromosomes are used to set the weights for a multi-layer perceptron (MLP)
- the MLP is fed inputs from sensors, returns an integer in range (0<=x<=3)
- MLP output is used to determine direction of movement of snake
- snakes provide their nearest snake with their last move
- this last move is also used in the decision making by the MLP
- if population goes extinct, snakes that died but had an above average score are revived
- if there are no suitable snakes to revive, the game ends
- at end of cycle, surviving snakes replicate to create next generation of snakes
- selection is done based on shared fitness
- if no snakes have good f3 fitness, individual fitness is used
- chromosomes of next generation snakes crossover and are mutated
- next generation commences
### Design Justification
Given the complexity of the problem, a simple mapping from chromosome to direction of movement was did not perform well. The snakes struggled to avoid eachother, often leading to the entire population being wiped out. Furthermore, using an MLP meant the snakes were able to learn significantly faster.

Upon consuming an apple turtle, a snake turtle spawns a tail turtle, which it links to itself. If the snake already has a tail, its tail spawns a linked tail of its own, effectively creating a train of linked turtles. tails do not have any capabilities of their own, and die when the snake leading them dies. The snakes start with 0 tails, allowing the observer to run larger populations. During experimentation, it was found that starting with tails led to the world getting crowded and the entire population dying out before they even learn how to avoid eachother.

The syllabus was light on NetLogo development, and so I found it easier to use the pre-installed Python extension with NumPy to implement and run the MLP. For the sake of speed and simplicity, only 2 hidden layers were implemented. All evolution however (selection, crossover, mutation, fitness sharing, etc.), is implemented directly in NetLogo.

f3 fitness is used only when there are snakes with a shared fitness that is significantly higher than the average individual fitness. If there are no snakes that meet this condition, the procedure defaults to individual fitness. This enables a 'best of both worlds' approach, where if there are a group of snakes with good f3 fitness, their genes are propogated forwards even if their individual fitnesses are poor, slightly increasing genetic variation. However, this is suboptimal either if the snakes are hardly related, or if there are snakes that perform so well that it increases the average individual fitness. In this situation, the individual fitness is used to ensure the next generation always gets better. This also has the side effect of reducing genetic variation, making f3 viable again next generation.

## Model Evaluation
In order to evaluate whether the evolution does indeed improve fitness, the averages of Total Length were compared between 2 types of populations. The first type used evolution to selectively decide which genes would be propogated to the next generation, using fitness, crossover, and mutation. The second type would simply randomly spawn the next generation, without being impacted by the performance of the previous generation.

The average is calculated as follows:
**`sum of total length at end of each generation / ((total number of generations + 1) population size per generation))`**

For each of the 2 types, a population of 6 snakes was initialised and run for 1000 generations. This was repeated 20 times for each type, giving us a dataset of 20 population averages for each type (total 40 data points). 6 was chosen as an initial population of 10 or more almost certainly leads to the "Tramline Strategy" being employed. With a population of 6, this is still extremely common, although it is now less severe.

### The Tramline Problem
Given the nature of the task (random apple spawn, random snake spawn, no walls), the population almost always converges on the same solution, that being the Tramline Strategy. I have coined this term for the way all the snakes move in a straight, regardless of their surroundings.

![EVAC2_tramlines.PNG](file:EVAC2_tramlines.PNG)
The Tramline Strategy

By simply moving forward in a straight line, the snakes will eventually find an apple that spawns in their line. Furthermore, there is very low risk of collisions with other snakes, especially if they are also moving in a straight line. This is effective to a certain degree when the population is large and the apple spawn chance is high. However, when not, this is extremely inefficient as large portions of the world remain unexplored. Using a smaller population size may sometimes lead to other movement patterns, but since surviving is the greatest marker for genes being propogated to the next generation, the entire population eventually employs this strategy. This is true even when the apple spawn chance is extremely low (< 0.01).
Even a counting down timer was implemented for each snake that resets when an apple is consumed (timer = 0, snake dies). The only noticeable effect this had was that populations were going extinct much more frequently.
Move sharing exacerbates this issue.

### Testing For Statistical Significance
To decide how to compare the datasets (parametric or non-parametric tests), their means, medians, and variances were calculated. This is shown in EVAC2.xlsx.
The reasons outlined in the spreadsheet enables us to use an upaired t-test on the datasets, which showed with great statistical significance that the means of the datasets are different. This means that using the evolution implemented yields a better result.

## Final Thoughts
Although there was a statistically significant improvement in fitness when using the evolution implemented, I believe there is still potential for the improvement to be greater. The hypothesis is that implementing the use of walls, and a fixed snake spawn position at the start of every generation would not only slightly reduce the stochasticity that is inherent in evolution, but also lead to better strategies than the aforementioned Tramline Strategy. Even simply adding walls would greatly increase the difference in fitness, as randomly generated populations with no evolution would never learn to avoid them.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.2.2
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
