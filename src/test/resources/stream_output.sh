#!/bin/bash

echo "BEGIN"
echo -n "BEGIN_remainder"

for i in 1 2 3
do
    echo "SEQ $i"
    echo -n "SEQ_${i}_remainder"
    sleep 1
done


echo "END"
echo -n "END_remainder"


