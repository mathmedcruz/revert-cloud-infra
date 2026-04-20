[![Build Status](https://dev.azure.com/hpcodeway/RunWay/_apis/build/status/runway.terragrunt-quickstart?branchName=master)](https://dev.azure.com/hpcodeway/RunWay/_build/latest?definitionId=1232&branchName=master)

# RunWay Terragrunt Quickstart

This template provides an example of how to manage your infrastructure using Terragrunt and Runway Terraform modules. Click on the "Use this template" button to create a new repository based on this template.

After creating a new repository, make sure you update the following files before you start adding your own configuration files:

- Update the build status badge. [Here are instructions on how to do this.](https://docs.microsoft.com/en-us/azure/devops/pipelines/create-first-pipeline?view=azure-devops&tabs=java%2Cyaml%2Cbrowser%2Ctfs-2018-2#add-a-status-badge-to-your-repository)
- Update the repository `CODEOWNERS` at [./github/CODEOWNERS](./github/CODEOWNERS) file.

## How is the code in this repo organized?

The code in this repo uses the following folder hierarchy:

```
. 
├── README.md
├── /account (e.g.: 264883513245 or mssi-sandbox-dev)
│   │
│   ├── account.hcl
│   │
│   ├── /_global
│   │
│   └── /region (e.g.: us-west-2)
│       │
│       ├── region.hcl
│       │
│       ├── /_regional
│       │
│       └── /environment (e.g.: dev)
│           │
│           ├── environment.hcl
│           │
│           ├── resource 1
│           │   └── terragrunt.hcl 
│           │
│           ├── resource 2
│           │   └── terragrunt.hcl
│           │
│           └── resource n
│               └── terragrunt.hcl
│
├── commons.hcl
└── terragrunt.hcl
```

Where:
* **Root**: At the top level of the repository, there is a terragrunt.hcl. The terragrunt.hcl file is setup to 
  dynamically create S3 buckets for the terraform state with the following format `AWS Account Id`-`AWS Region`-remote-state. 
  There is also a common.hcl that should be updated with the correct value for your application (`app_name`).

* **Account**: At the top level is your AWS account. You can use this template with multiple AWS accounts, 
  however the recommended approach is to separate AWS account in different GitHub repositories.

* **Region**: Within each account, there will be one or more [AWS
  regions](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html), such as
  `us-east-1`, `eu-west-1`, and `ap-southeast-2`, where you've deployed resources. There may also be a `_global`
  folder that defines resources that are available across all the AWS regions in this account, such as IAM users,
  Route 53 hosted zones, and CloudTrail.

* **Environment**: Within each region, there will be one or more "environments", such as `dev`, `staging`, `pro`, etc. Typically,
  an environment will correspond to a single [AWS Virtual Private Cloud (VPC)](https://aws.amazon.com/vpc/), which
  isolates that environment from everything else in that AWS account. There may also be a `_regional` folder
  that defines resources that are available across all the environments in this AWS region, such as SNS topics, and ECR repos.

* **Resource**: Within each environment, you deploy all the resources for that environment, such as EC2 Instances, Auto
  Scaling Groups, EKS Clusters, Databases, Load Balancers, and so on. Note that the Terraform code for most of these
  resources lives in the [GitHub Enterprise Runway Organization](https://github.azc.ext.hp.com/runway).
  
## Creating and using root (account) level variables

In the situation where you have multiple AWS accounts or regions, you often have to pass common variables down to each
of your modules. Rather than copy/pasting the same variables into each `terragrunt.hcl` file, in every region, and in
every environment, you can inherit them from the `inputs` defined in the root `terragrunt.hcl` file.

## Running terragrunt locally

### Validate

Go to the `account` top-level folder and run `terragrunt run-all validate` to check if the syntax of the terragrunt HCL files are correct.

### Plan

Go to the `account` top-level folder and run `terragrunt run-all plan` to create an execution plan.

### Apply

Go to the `account` top-level folder and run `terragrunt run-all apply` to provisioning all resources described in the execution plan.

### Destroy

Go to the `account` top-level folder and run `terragrunt run-all destroy` to delete the provisioned infrastructure completely.

## Running terragrunt with CodeWay

This template provides a `codeway.yaml` file that makes use of the [terragrunt-live-infrastructure](https://pages.github.azc.ext.hp.com/codeway/templates/docs/v1.0/pipeline-templates/runway-terragrunt-live-infrastructure-tf-v1.3.x.html) CodeWay template. Follow the instructions available in the CodeWay template documentation to configure your CodeWay project accordingly.

### Destroying resources via pipeline

As your infrastructure evolves, at some point you'll have to destroy resources previously created. Follow the instructions available at [here](https://pages.github.azc.ext.hp.com/codeway/templates/docs/v1.0/pipeline-templates/runway-terragrunt-live-infrastructure-tf-v1.3.x.html#destroy-workflow) to remove unnecessary terraform modules from your infrastructure.

### Note: TLS policy enforcement

HP Cybersecurity mandates the use of TLS 1.2 or higher for all network communication. This includes access to private and public S3 buckets.
At the moment, Terragrunt doesn't support defining S3 policies when the remote state bucket is created. In this case, HP Cybersecurity will automatically add a policy enforcing the use of TLS1.2 or higher. If you prefer, you can manually add the policy after the remote state bucket is created. An example of such policy can be found [here](https://github.azc.ext.hp.com/runway/terraform-aws-s3/issues/10)

## Issues

### Bugs

If you have found a bug, follow the instructions below:

- Spend a small amount of time giving due diligence to the issue tracker. Your issue might be a duplicate.
- Open a [new issue](../../issues/new).
- Inform what role you are using.
- Remember, users might be searching for your issue in the future, so please give it a meaningful title to helps others.

### Features

If you need a new provisioning role or new policies attached to an existing role, follow the steps below.

- Open a [new issue](../../issues/new).
- Clearly define the use case and the required policies.
- Feel free to code it yourself. Open up a pull request and happy coding.

## Contributing

Pull requests are welcome on GitHub. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributors' Guide](.github/CONTRIBUTING.md).
