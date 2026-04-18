use v5.38;
use Test::More;
use Test::Exception;

use Balance::FuzzyName qw(normalize matches);

# --- normalize ---

subtest 'normalize: plain name lowercased and trimmed' => sub {
    is(normalize('Breaking Bad'), 'breaking bad', 'basic name');
};

subtest 'normalize: strips trailing (YYYY)' => sub {
    is(normalize('Lost (2004)'),   'lost',          'strips year');
    is(normalize('Lost  (2004) '), 'lost',          'strips year with spaces');
};

subtest 'normalize: inverts trailing The' => sub {
    is(normalize('Office, The'),         'the office',         'The');
    is(normalize('Walking Dead, The'),   'the walking dead',   'multi-word + The');
    is(normalize('Walking Dead, the'),   'the walking dead',   'lowercase the');
};

subtest 'normalize: inverts trailing A' => sub {
    is(normalize('Knight, A'),   'a knight',   'A');
};

subtest 'normalize: inverts trailing An' => sub {
    is(normalize('Inspector, An'),  'an inspector', 'An');
};

subtest 'normalize: lowercases' => sub {
    is(normalize('SHOUTING'),  'shouting',  'all caps');
    is(normalize('MiXeD CaSe'), 'mixed case', 'mixed case');
};

subtest 'normalize: replaces dots with spaces' => sub {
    is(normalize('The.Office.US'),  'the office us',  'dots replaced');
};

subtest 'normalize: replaces underscores with spaces' => sub {
    is(normalize('The_Office_US'),  'the office us',  'underscores replaced');
};

subtest 'normalize: replaces hyphens with spaces' => sub {
    is(normalize('Hawkeye-Marvel'), 'hawkeye marvel', 'hyphens replaced');
};

subtest 'normalize: collapses multiple whitespace' => sub {
    is(normalize("Too  Many   Spaces"), 'too many spaces', 'multiple spaces collapsed');
};

subtest 'normalize: NFC normalization (precomposed vs decomposed accent)' => sub {
    require Unicode::Normalize;
    my $precomposed  = "Caf\x{00e9}";          # é as single codepoint
    my $decomposed   = "Cafe\x{0301}";         # e + combining acute
    is(normalize($precomposed), normalize($decomposed), 'NFC makes accented chars equal');
};

subtest 'normalize: combined — year + article + dots' => sub {
    is(normalize('The.Wire, The (2002)'), 'the the wire', 'combined transformations');
};

# --- matches ---

subtest 'matches: identical names' => sub {
    ok(matches('Breaking Bad', 'Breaking Bad'), 'same name');
};

subtest 'matches: case-insensitive' => sub {
    ok(matches('breaking bad', 'Breaking Bad'), 'different case');
};

subtest 'matches: different names return false' => sub {
    ok(!matches('Breaking Bad', 'Better Call Saul'), 'different names');
};

subtest 'matches: year-stripped match' => sub {
    ok(matches('Lost (2004)', 'Lost'), 'year stripped');
};

subtest 'matches: article inversion match' => sub {
    ok(matches('Office, The', 'The Office'), 'article inverted');
};

subtest 'matches: separator-normalised match' => sub {
    ok(matches('The.Office.US', 'The Office US'), 'dots match spaces');
};

done_testing;
