// Create a docker image to be used as a base layer for all lambda services
// rebuild that image each time there is a change in kit_dart_utils or kit_models
import 'dart:io';


void main(List<String> arguments) async {
  startApp();
}

//----------------------------------------------------------------------------------------------------------------------
Future<void> startApp() async {

  // Create a temporary directory

  final tempDir = Directory('../../kit_docker_build_lambda_base_image_temp_project');

  if (!tempDir.existsSync()) {
    tempDir.createSync();
  }

  // process different steps to build and deploy image
  await buildTemporaryDartProject(tempDir);
  await buildTemporaryDockerfile(tempDir);
  await buildAndTagDockerImage(tempDir);

  exit(0);
}

//----------------------------------------------------------------------------------------------------------------------
Future<void> buildTemporaryDartProject(Directory tempDir) async {

  // Create pubspec.yaml
  final pubspecFile = File('${tempDir.path}/pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    pubspecFile.createSync();
  }
  pubspecFile.writeAsStringSync('''
name: kit_docker_build_lambda_base_image
version: 1.0.0
publish_to: none
environment:
  sdk: ">=2.17.0 <3.0.0"
dependencies:
  kit_lambda_utils:
    git: https://github.com/pierreduv/kit_lambda_utils
  aws_lambda_dart_runtime: ^1.1.0
  aws_dynamodb_api: ^2.0.0
  aws_common: ^0.3.0
  aws_signature_v4: ^0.3.0
  characters: ^1.2.1
  flinq: ^2.0.2
  meta: '^1.1.8'
  uuid: ^3.0.7
''');
}




//----------------------------------------------------------------------------------------------------------------------
Future<void> buildTemporaryDockerfile(Directory tempDir) async {
  final dockerFile = File('${tempDir.path}/Dockerfile');
  dockerFile.writeAsStringSync('''
FROM dart as kit_lambda_base
COPY . /root
RUN dart pub get
LABEL build-stage=kit_lambda_base
''');

  print('Dockerfile created in temporary directory!');
}


//----------------------------------------------------------------------------------------------------------------------
Future<void> buildAndTagDockerImage(Directory tempDir) async {
  try {
    var processResult = await Process.run('flutter', ['clean'], workingDirectory: tempDir.path);
    processResult = await Process.run('docker', ['system', 'prune', '-f']);
    processResult = await Process.run('docker', ['build', '-t',  'kit_lambda_base', '.', '--target', 'kit_lambda_base'], workingDirectory: tempDir.path);
    print(processResult.stderr);
    print('Docker kit_lambda_base image built and tagged successfully!');
  } catch (error) {
    print('Error: $error');
  }
}

