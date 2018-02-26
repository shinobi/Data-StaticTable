use v6;
use Test;
use Data::StaticTable;

diag "== Extra features tests ==";
my $t1 = Data::StaticTable.new(
  <A B C>,
  (1 .. 9)
);
diag $t1.display;
diag "== Serialization and EVAL test ==";
my $t1-copy = EVAL $t1.perl;
diag $t1-copy.perl;
diag "== Comparison test ==";
my $t1-clone = $t1.clone();
my $t2 = Data::StaticTable.new(
  <A B C>,
  (1,2,3,4,5,6,7,0,9) # The 0 before the 9 is the only difference
);
ok($t1 eqv $t1-copy, "Comparison works (equal to EVALuated copy from 'perl' method)");
ok($t1 eqv $t1-clone, "Comparison works (equal to clone)");
ok(($t1 eqv $t2) == False, "Comparison works (distinct)");

diag "== Filler tests ==";
my $t3 = Data::StaticTable.new(
  <A B C>,
  (1,2,3,
   4,5,6,
   7),     # 2 last shoud be fillers
   filler => 'N/A'
);
diag $t3.display;
ok($t3[3]<C> eq 'N/A', 'Filler is correct');
my $t3-clone = $t3.clone();
ok($t3 eqv $t3-clone, "Cloning with filler works");

done-testing;
