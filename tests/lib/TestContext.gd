class_name TestContext
extends RefCounted
## Assertion collector for one test. Failures are recorded, never thrown, so
## every check in a test runs and reports.

var name: String
var checks: int = 0
var failures: Array[String] = []
var _expected_errors: int = 0


func _init(test_name: String) -> void:
	name = test_name


func ok(condition: bool, msg: String) -> void:
	checks += 1
	if not condition:
		failures.append(msg)


## Numbers compare by value at any depth, so a JSON float 5.0 equals an int 5
## and [5.0, 15.0] equals [5, 15]. Every other type must match exactly.
func eq(actual, expected, msg: String) -> void:
	checks += 1
	if not _same(actual, expected):
		failures.append("%s: expected %s, got %s" % [msg, var_to_str(expected), var_to_str(actual)])


func near(actual: float, expected: float, tolerance: float, msg: String) -> void:
	checks += 1
	if absf(actual - expected) > tolerance:
		failures.append("%s: expected %s ± %s, got %s" % [msg, expected, tolerance, actual])


func contains(haystack: String, needle: String, msg: String) -> void:
	checks += 1
	if not needle in haystack:
		failures.append("%s: '%s' not found in '%s'" % [msg, needle, haystack])


## Declares that this test deliberately triggers `count` logged errors.
func expect_errors(count: int) -> void:
	_expected_errors += count


func settle_errors(logged: Array[String]) -> void:
	if logged.size() != _expected_errors:
		failures.append("logged %d error(s), expected %d:" % [logged.size(), _expected_errors])
		for e in logged:
			failures.append("    " + e)


func passed() -> bool:
	return failures.is_empty()


static func _same(a, b) -> bool:
	var num := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in num and typeof(b) in num:
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if typeof(a) == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]):
				return false
		return true
	return a == b
