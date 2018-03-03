use v6;
use Test;
use Data::StaticTable;

diag "== Testing indexes ==";
my $t1 = Data::StaticTable.new(
     <Attr          Dim1      Dim2    Dim3    Dim4>,
    (
    'attribute-1',  1,         21,     3,      'D+', # Row 1
    'attribute-2',  4,         51,     6,      'B+', # Row 2
    'attribute-3',  7,         80,     9,      'A-', # Row 3
    'attribute-4', ('ALPHA',                         # \\\\\
                    'BETA',                          # Row 4
                     3.0),     5,      6,      'A++',# \\\\\
    'attribute-10', 0,         0,      0,      'B+', # Row 5
    'attribute-11', (-2 .. 2), Nil,    Nil,    'B+'  # Row 6
    )
);
diag $t1.display;

diag "== Check indexes ==";
my $q1  = Data::StaticTable::Query.new($t1);
for ($t1.header) -> $h { $q1.add-index($h) }; #--- Generate all indexes

ok($q1<Dim4>.elems == 4, "Index of Dim4 has 4 elements");
ok($q1<Dim1>:exists == True, "We can check if a column index has been generated");
ok($q1<DimX>:exists == False, "We can check if a column index has not been generated");
ok($q1<Dim1><7>:exists == True, "We can see if the value 7 exists in a indexed column");
ok($q1<Dim1><9>:exists == False, "We can see if the value 9 does not exist in a indexed column");
ok($q1<Dim3><6>.elems == 2, "We can check that the value 6 appears in 2 rows in column Dim3");
ok($q1<Dim3><6> ~~ (2, 4), "We can check that the value 6 appears in column Dim3, rows 2 and 4");

diag "== Searching without index ==";
my $q2 = Data::StaticTable::Query.new($t1);
ok($q2.grep("Dim3", rx/6/)                 ~~ (2, 4),    "Grep test returns rows 2,4");
ok($q2.grep("Dim3", any(rx/9/, rx/6/))     ~~ (2, 3, 4), "Grep test returns rows 2,3,4" );
ok($q2.grep("Dim2", one(rx/1/, rx/5/))     ~~ (1, 4),    "Grep test returns rows 1,4");
ok($q2.grep("Dim2", any(rx/1/, rx/5/))     ~~ (1, 2, 4), "Grep test returns rows 1,2,4");
ok($q2.grep("Dim2", all(rx/1/, rx/5/))     ~~ (2,),      "Grep test returns row 2");
ok($q2.grep("Dim2", none(rx/1/, rx/5/))    ~~ (3, 5),    "Grep test returns rows 3,5");
ok($q2.grep("Dim1", any(rx/ALPHA/, rx/0/)) ~~ (4, 5, 6), "Grep test returns rows 4,5,6");

ok(
    $q1.grep("Dim2", any(rx/1/, rx/5/)) ~~ $q2.grep("Dim2", any(rx/1/, rx/5/)),
    "Grep with index and without are equivalent (#1)"
);

ok(
    $q1.grep("Dim2", all(rx/1/, rx/5/)) ~~ $q2.grep("Dim2", all(rx/1/, rx/5/)),
    "Grep with index and without are equivalent (#2)"
);

ok(
    $q1.grep("Dim2", none(rx/1/, rx/5/)) ~~ $q2.grep("Dim2", none(rx/1/, rx/5/)),
    "Grep with index and without are equivalent (#3)"
);

diag "== Create a new table from grep results ==";
my Data::StaticTable::Position @rows;
@rows.append($q2.grep("Dim2", one(rx/1/, rx/5/)));
@rows.append($q2.grep("Dim2", all(rx/1/, rx/5/)));

my $t2 = $t1.take(@rows);
#-- This should generate a StaticTable with rows 1, 4 and 2. IN THAT ORDER.
diag $t2.display;

ok($t2.rows == 3, "Resulting StaticTable has 3 rows");
ok($t2[3]{'Dim2'} == 51, "Right value found in Col Dim2, Row 3");

diag "== Index creation at construction ==";
my Data::StaticTable::Position @two-rows = (1, 2);
my $t3 = $t1.take(@two-rows);
my $q31 = Data::StaticTable::Query.new($t3, <Dim1 Dim2>);
my $q32 = Data::StaticTable::Query.new($t3, 'Dim1', 'Dim2');
ok($q31.kv.perl eqv $q32.kv.perl, "Equivalence using slurpy array for index spec on construction");

throws-like
{ my $ = Data::StaticTable::Query.new($t3, 'Dim1', 'DimXXXXX') },
X::Data::StaticTable,
"Construction fails when specifiying a heading that does not exist";

diag "== Serialization and EVAL test ==";
my $q33 = EVAL $q31.perl;
diag $q33.perl;
ok($q31.perl eq $q33.perl, "Can be serialized using .perl method");

diag "== More grep testing ==";
my $t4 = Data::StaticTable.new(
    <Countries  Import      Tons>,
    (
    'US PE CL', 'Copper',    100,
    'US RU',    'Alcohol',   50,
    'IL UK',    'Processor', 12,
    'UK',       'Tuxedo',    1,
    'JP CN',    'Tuna',      10
    )
);
my $q4 = Data::StaticTable::Query.new($t4, $t4.header);


done-testing;
