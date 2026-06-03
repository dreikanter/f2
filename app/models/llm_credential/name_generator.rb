class LlmCredential::NameGenerator
  ADJECTIVES = %w[
    aged
    agile
    amber
    ample
    ancient
    ardent
    azure
    bare
    bold
    brave
    bright
    brisk
    broad
    calm
    clean
    clear
    clever
    cold
    cool
    cozy
    crisp
    dark
    deep
    deft
    dense
    divine
    dreamy
    dusty
    eager
    early
    epic
    fair
    fierce
    fine
    firm
    fleet
    free
    fresh
    frosty
    full
    gentle
    glad
    golden
    graceful
    grand
    hardy
    hazy
    high
    icy
    jolly
    keen
    large
    light
    lofty
    lone
    loyal
    lush
    mellow
    mild
    mighty
    muted
    near
    nimble
    noble
    open
    outer
    pale
    plain
    plush
    prime
    proud
    pure
    quick
    quiet
    raw
    ready
    ripe
    rocky
    round
    royal
    rugged
    rustic
    sacred
    sandy
    serene
    silent
    slim
    smooth
    snowy
    soft
    solemn
    solid
    sparse
    stark
    swift
    true
    vast
    warm
    wild
    wise
  ].freeze

  NOUNS = %w[
    acorn
    albatross
    almond
    anchor
    banana
    basalt
    beacon
    birch
    bison
    boulder
    brook
    cabin
    cactus
    canopy
    canyon
    cascade
    cavern
    cedar
    cherry
    cinder
    citrus
    cliff
    clover
    comet
    copper
    coral
    crystal
    dawn
    delta
    dew
    dome
    dove
    dusk
    echo
    ember
    falcon
    fern
    field
    flint
    foam
    forge
    fossil
    fox
    glacier
    grove
    harbor
    hemlock
    hollow
    horizon
    inlet
    iris
    island
    ivory
    jade
    jasper
    juniper
    kelp
    knoll
    lagoon
    lantern
    lark
    laurel
    lavender
    ledge
    linden
    lotus
    maple
    marble
    marsh
    meadow
    mesa
    mint
    mist
    moor
    moss
    nectar
    oak
    obsidian
    opal
    otter
    peak
    pebble
    pine
    plum
    poplar
    quartz
    quill
    ravine
    reed
    ridge
    river
    rosewood
    ruin
    sage
    salmon
    sandstone
    summit
    thunder
    walnut
    willow
  ].freeze

  def initialize(label, existing)
    @label = label
    @existing = existing
  end

  def generate
    pair = lazy_shuffle(ADJECTIVES).flat_map { |adj|
      lazy_shuffle(NOUNS).map { |noun| [adj, noun] }
    }.find { |adj, noun| !@existing.include?("#{@label} #{adj.capitalize} #{noun.capitalize}") }

    if pair
      adj, noun = pair
      "#{@label} #{adj.capitalize} #{noun.capitalize}"
    else
      n = 1
      n += 1 while @existing.include?("#{@label} #{n}")
      "#{@label} #{n}"
    end
  end

  private

  def lazy_shuffle(arr)
    Enumerator.new do |y|
      a = arr.dup
      a.size.times do |i|
        j = rand(i...a.size)
        a[i], a[j] = a[j], a[i]
        y << a[i]
      end
    end.lazy
  end
end
