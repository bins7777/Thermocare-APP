const productVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.2',
);
const productBuild = String.fromEnvironment('APP_BUILD', defaultValue: '4');
