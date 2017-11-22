<?php

$in = [
    ["name" => "foo"],
    ["name" => "bar"],
    ["name" => "baz"],
];

var_dump(array_map(function($val) { return $val['name']; }, $in));
