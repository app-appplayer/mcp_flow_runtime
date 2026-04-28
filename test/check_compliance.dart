import 'dart:io';

void main() async {
  final tests = [
    'action_types_test.dart',
    'configuration_test.dart', 
    'expression_language_test.dart',
    'state_management_test.dart',
    'trigger_types_test.dart'
  ];
  
  int totalPassed = 0;
  int totalFailed = 0;
  int totalSkipped = 0;
  
  for (final test in tests) {
    print('\nRunning $test...');
    final result = await Process.run('dart', ['test', 'test/spec_compliance/$test']);
    
    // Parse output for test counts
    final output = result.stdout.toString();
    final lines = output.split('\n');
    
    for (final line in lines) {
      if (line.contains('[32m+') && line.contains('[0m:')) {
        // Extract passed count
        final match = RegExp(r'\[32m\+(\d+)\[0m').firstMatch(line);
        if (match != null) {
          totalPassed = int.parse(match.group(1)!);
        }
      }
      if (line.contains('[31m -') && line.contains('[0m:')) {
        // Extract failed count
        final match = RegExp(r'\[31m -(\d+)\[0m').firstMatch(line);
        if (match != null) {
          totalFailed = int.parse(match.group(1)!);
        }
      }
      if (line.contains('[33m ~') && line.contains('[0m:')) {
        // Extract skipped count
        final match = RegExp(r'\[33m ~(\d+)\[0m').firstMatch(line);
        if (match != null) {
          totalSkipped = int.parse(match.group(1)!);
        }
      }
    }
  }
  
  final total = totalPassed + totalFailed + totalSkipped;
  final percentage = total > 0 ? (totalPassed / total * 100).toStringAsFixed(1) : '0.0';
  
  print('\n========== SPEC COMPLIANCE SUMMARY ==========');
  print('Total tests: $total');
  print('Passed: $totalPassed');
  print('Failed: $totalFailed');
  print('Skipped: $totalSkipped');
  print('Compliance: $percentage%');
  print('============================================');
}