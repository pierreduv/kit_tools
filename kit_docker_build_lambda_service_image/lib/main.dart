// Create a docker image to be used as a service layer for all lambda services
// rebuild that image each time there is a change in kit_dart_utils or kit_models
import 'dart:io';
import 'dart:isolate';
import 'package:kit_dart_utils/_library.dart';
import 'package:kit_dart_utils/registry/registry_service_impl_getIt.dart';
import 'package:aws_lambda_api/lambda-2015-03-31.dart';
import 'package:aws_apigateway_api/apigateway-2015-07-09.dart' as apigw;

Directory? _sourcesDirectory;

Directory get sourcesDirectory {
  if (_sourcesDirectory == null) {
    const sourcesDirectoryPath = '/users/pierreduval/pikobasic/kit_lambda_sources/lib/';
    _sourcesDirectory = Directory(sourcesDirectoryPath);
  }
  return _sourcesDirectory!;
}


class RootBundle {
  static RootBundle? _instance;

  static RootBundle get instance {
    _instance ??= RootBundle();
    return _instance!;
  }

  String loadString(String filePath) {
    var file =  File(filePath);
    return file.readAsStringSync();
  }
}



void main(List<String> arguments) async {
  startApp();
}

//----------------------------------------------------------------------------------------------------------------------
Future<void> startApp() async {

  var rootBundle = RootBundle.instance;
  var configString = rootBundle.loadString("assets/config.json");

  RegistryService.setInstance(RegistryServiceImplGetIt());
  var registry = RegistryService.instance;
  await buildAndDeployServices();
}


//----------------------------------------------------------------------------------------------------------------------
Future<void> buildAndDeployServices() async {
  // read service source files
  final dir = sourcesDirectory;
  List<FileSystemEntity> files = dir.listSync(recursive: false, followLinks: false);

  // processResult each file
  for (var file in files) {
    if (file is! File) continue;
    // skip files not ending with .dart
    if (!file.path.endsWith('.dart')) continue;
    // keep only the end of the path as the filename
    var fileName = file.path
        .split('/')
        .last;
    var serviceName = fileName.replaceEnd('.dart', '');
    var serviceSourceCode = file.readAsStringSync();
    print (serviceName);
    await buildAndDeployService(serviceName, serviceSourceCode);
  }
  exit(0);
}


//----------------------------------------------------------------------------------------------------------------------
Future<void> buildAndDeployService(String serviceName, String serviceSourceCode) async {
  print('-------------------------------------------------------');
  print(serviceName);
  print(serviceSourceCode);


  // Create a temporary directory
  final tempDir = Directory('/users/pierreduval//kit_docker_build_lambda_service_image_temp_project');

  if (tempDir.existsSync()) {
    tempDir.deleteSync(recursive: true);
  }
  tempDir.createSync();


  // processResult different steps to build and deploy image
  await buildTemporaryDartProject(serviceName, serviceSourceCode, tempDir);
  await buildTemporaryDockerfile(serviceName, tempDir);
  await buildAndTagDockerImage(serviceName, tempDir);
  await uploadDockerImageToAwsEcr(serviceName);
  await createLambda(serviceName);
  await createApiGatewayResourceForLambda(serviceName);
}

//----------------------------------------------------------------------------------------------------------------------
void scheduleExitHandler(Function handler) {
  ProcessSignal.sigint.watch().listen((_) => handler());
  ProcessSignal.sigterm.watch().listen((_) => handler());
}


//----------------------------------------------------------------------------------------------------------------------
Future<void> buildTemporaryDartProject(String serviceName, String serviceSourceCode, Directory tempDir) async {
// Create lib directory
  final libDir = Directory('${tempDir.path}/lib');
  libDir.createSync();

  // Create service Dart file
  final serviceDartFile = File('${libDir.path}/$serviceName.dart');
  serviceDartFile.writeAsStringSync(serviceSourceCode);
  // Create build directory
  final binDir = Directory('${tempDir.path}/bin');
  binDir.createSync();
  print('Project "$serviceName" created in temporary directory!');
}




//----------------------------------------------------------------------------------------------------------------------
Future<void> buildTemporaryDockerfile(String serviceName, Directory tempDir) async {
  final dockerFile = File('${tempDir.path}/Dockerfile');
  dockerFile.writeAsStringSync('''
FROM kit_lambda_utils as compiler
WORKDIR /app
COPY --from=kit_lambda_utils /app/bin/kit_lambda_utils .
RUN dart pub get
RUN dart compile exe lib/main.dart -o ./bin/$serviceName
FROM public.ecr.aws/lambda/provided:al2
COPY --from=compiler app/bin/service_1 /bin/service_1
ENTRYPOINT ["main"]
'''); // Modified to correct CMD usage for multi-stage builds

  print('Dockerfile created in temporary directory!');
}

/*
FROM scratch
COPY --from=compiler app/bin/$serviceName /bin/$serviceName
RUN chmod +x ./bin/service_1
 */
//----------------------------------------------------------------------------------------------------------------------
Future<void> buildAndTagDockerImage(String serviceName, Directory tempDir) async {
  try {
    var processResult = await Process.run('docker', ['system', 'prune', '-f']);
    processResult = await Process.run('docker', ['build', '-t', serviceName, '.'], workingDirectory: tempDir.path);
    print(processResult.stderr);
    processResult = await Process.run(
        'docker', ['tag', '$serviceName:latest', '058264167383.dkr.ecr.ca-central-1.amazonaws.com/$serviceName'],
        workingDirectory: tempDir.path);
    print(processResult.stderr);
    print('Docker image $serviceName built and tagged successfully!');
  } catch (error) {
    print('Error: $error');
  }
}
//----------------------------------------------------------------------------------------------------------------------
Future<void> uploadDockerImageToAwsEcr(String serviceName) async {
  // Login to ECR (using the Docker API for security)

  // create a temporary session-token
  var p0 = await Process.start('aws', ['sts', 'get-session-token']);
  print(p0.stdout);
  print(p0.stderr);

  // Get the login command for ECR authentication (replace with your preferred method)
  var awsEcrGetLoginPassword= 'aws ecr get-login-password --region ca-central-1';
  var dockerLoginCommand = 'docker login --username AWS --password-stdin 058264167383.dkr.ecr.ca-central-1.amazonaws.com';

  var p1 = await Process.start('/bin/sh', ['-c', 'aws ecr get-login-password --region ca-central-1 | docker login --username AWS --password-stdin 058264167383.dkr.ecr.ca-central-1.amazonaws.com']);
  print(p1.stdout);
  print(p1.stderr);
  var p2 = await Process.run('docker', ['images']);
  print(p2.stdout);

  // Push the image to ECR
  print(serviceName);
  var p3 = await Process.run('docker', ['push', '058264167383.dkr.ecr.ca-central-1.amazonaws.com/$serviceName']);
  print(p3.stdout);
  print(p3.stderr);
}


//----------------------------------------------------------------------------------------------------------------------
Future<void> createLambda(String serviceName) async {

  // Replace with your AWS credentials
  final String awsAccessKeyId = 'AKIAQ3EGQUPLV2KJBVPU';
  final String awsSecretAccessKey = 'gMCzMVRoKhgVfeNAvqt8frR7BGrAmqaazBuEtzkQ';

  // Replace with your actual values
  final String region = 'ca-central-1';
  final String handler = 'handler';  // Lambda handler function

  // Replace with the name of your function and Docker image details
  final String dockerImageUri = '058264167383.dkr.ecr.<region>.amazonaws.com/$serviceName';
  final String roleArn = '<your-iam-role-arn>'; // Role with necessary IAM permissions

  final creds = AwsClientCredentials(accessKey: awsAccessKeyId, secretKey: awsSecretAccessKey);
  final client = Lambda(region: region, credentials: creds);

  var lambdaExists = true;
  try {
    // Get function details to check if it exists
    GetFunctionResponse getFunctionResponse = await client.getFunction(functionName: serviceName);
  }  catch (e) {
    lambdaExists = false;
  }

  if (lambdaExists) {

    print('Lambda function updated successfully.');
  }
  else {
    print('before function code.');
    FunctionCode functionCode = FunctionCode(imageUri: '058264167383.dkr.ecr.ca-central-1.amazonaws.com/service_1:latest');
    print('before create function');

    await client.createFunction(
        code: functionCode,
        functionName: serviceName,
        role: 'arn:aws:iam::058264167383:role/service-role/dart_server-role-cdtgx2d9',
        packageType: PackageType.image
    );
    print('function created successfully.');  }

}


Future<void> createApiGatewayResourceForLambda(String serviceName) async {
  final String apiName = 'LambdasApiGateway';
  final String apiStage = 'dev';
  final String apiPath = '/your-path';
  final String httpMethod = 'POST'; // Adjust HTTP method as needed

  // Replace with your AWS credentials
  final String awsAccessKeyId = 'AKIAQ3EGQUPLV2KJBVPU';
  final String awsSecretAccessKey = 'gMCzMVRoKhgVfeNAvqt8frR7BGrAmqaazBuEtzkQ';

  // Replace with your actual values
  final String region = 'ca-central-1';
  final String handler = 'handler'; // Lambda handler function

  // Replace with the name of your function and Docker image details
  final String dockerImageUri = '058264167383.dkr.ecr.<region>.amazonaws.com/$serviceName';
  final String roleArn = '<your-iam-role-arn>'; // Role with necessary IAM permissions

  final creds = AwsClientCredentials(accessKey: awsAccessKeyId, secretKey: awsSecretAccessKey);
  final client = apigw.APIGateway(region: region, credentials: creds);

  apigw.RestApis restApis = await client.getRestApis();
  apigw.RestApi? restApi = restApis.items?.firstWhere((restApi) => restApi.name == apiName);
  print('restApiItemId: ${restApi!.id}');

  apigw.Resources resources = await client.getResources(restApiId: restApi.id!);
  apigw.Resource? rootResource = resources.items?.firstWhere((resource) => resource.path == '/');
  bool? resourceExists = resources.items?.any((resource) => resource.path == '/$serviceName');
  if (resourceExists != null && resourceExists ) return;

  // if the resource doesn't exist create it
  await client.createResource(restApiId: restApi.id!, parentId: rootResource!.id!, pathPart: serviceName);
}

/*
  // API Gateway method configuration (assuming integration with the Lambda)
  final method = apigw.Method(
  httpMethod: httpMethod,
  integrationConfiguration: apigw.IntegrationConfiguration(
  type: apigw.IntegrationType.awsProxy,
  integrationHttpMethod: httpMethod,
  uri: lambdaClient.arnForFunction(FunctionName: functionName),
  ),
  );

  // Create or update the API Gateway method
  final existingMethod = await client.getMethod(
  restApiId: await _getApiId(client, apiName),
  resourcePath: '/$apiPath');
  if (existingMethod == null) {
  await client.createMethod(restApiId: await _getApiId(client, apiName), pathPart: apiPath, parameters: method);
  print('API Gateway method created successfully!');
  } else {
  await client.updateMethod(
  restApiId: await _getApiId(client, apiName),
  pathPart: apiPath,
  parameters: method);
  print('API Gateway method updated successfully!');
  }

  print('Lambda function and API Gateway resource configured!');
}
   */
