if [ -z ${PROJ_HOME} ]; then
    export PROJ_HOME="$(pwd)";
fi


# Define default environment variables related to AWS account
export PROJECT_NAME="spectre"
export DEFAULT_REPOSITORY_NAME="spectre"
export DEFAULT_EMAIL="<YOUR_EMAIL>"
export DEFAULT_ACCOUNT_NUMBER="962372302662"
export DEFAULT_REGION="ap-southeast-1"


# Define environment variables related to CloudFormation
export CFN_INFRA="cfn-infra"
export CFN_SERVICE="cfn-service"
export CFN_STACK_NAME_INFRA="${PROJECT_NAME}-infra"
export CFN_STACK_NAME_SERVICE="${PROJECT_NAME}-service"

export CFN_S3_BUCKET_INFRA="${DEFAULT_ACCOUNT_NUMBER}-${PROJECT_NAME}-${CFN_INFRA}"
export CFN_S3_BUCKET_SERVICE="${DEFAULT_ACCOUNT_NUMBER}-${PROJECT_NAME}-${CFN_SERVICE}"
export CFN_S3_BASE_URL_INFRA="https://${CFN_S3_BUCKET_INFRA}.s3-${DEFAULT_REGION}.amazonaws.com"
export CFN_S3_BASE_URL_SERVICE="https://${CFN_S3_BUCKET_SERVICE}.s3-${DEFAULT_REGION}.amazonaws.com"

export S3_BUCKET_CLOUDTRAIL="${DEFAULT_ACCOUNT_NUMBER}-${PROJECT_NAME}-cloudtrail"
export S3_BUCKET_ARTIFACT="${DEFAULT_ACCOUNT_NUMBER}-${PROJECT_NAME}-artifacts"

# Define environment variables related to the CodeCommit repository
export REPOSITORY_INFRA="${PROJECT_NAME}-infra"
export REPOSITORY_SERVICE="${PROJECT_NAME}-service"


##################################################################################
# Util methods
##################################################################################
function _print_info() {
    echo -e "-------------------------------------------------------------------------------
    $@
-------------------------------------------------------------------------------"
}

function _s3_sync_cfn_templates() {
    local local_path=$1
    local bucket_name=$2

    aws s3 sync \
        ${local_path} \
        s3://${bucket_name}/ \
            --exclude '.*.sh' \
            --exclude '*.DS_Store' \
            --exclude '*.git/*' \
            --exclude '*.pyc'
}


# This function initializes all dependencies needed for project
#
function _init_dependencies() {
    _print_info "---> Creating Infra S3 Bucket ..."
    aws s3 mb "s3://${CFN_S3_BUCKET_INFRA}"

    _print_info "---> Enable bucket '${CFN_S3_BUCKET_INFRA}' versioning ..."
    aws s3api put-bucket-versioning \
        --bucket "${CFN_S3_BUCKET_INFRA}" \
        --versioning-configuration Status=Enabled

    _print_info "---> Creating Service S3 Bucket ..."
    aws s3 mb "s3://${CFN_S3_BUCKET_SERVICE}"

    _print_info "---> Enable bucket '${CFN_S3_BUCKET_SERVICE}' versioning ..."
    aws s3api put-bucket-versioning \
        --bucket "${CFN_S3_BUCKET_SERVICE}" \
        --versioning-configuration Status=Enabled
}
alias "${PROJECT_NAME}-init-dependencies"="_init_dependencies"


##############################################################################
### S3 BUCKET
##############################################################################

# This functions syncs all CloudFormation templates to S3 bucket
#
function s3-sync-infra-cfn-templates() {
    _print_info "---> Syncing CloudFormation infra templates to S3 bucket ..."
    _s3_sync_cfn_templates "${PROJ_HOME}/${CFN_INFRA}" ${CFN_S3_BUCKET_INFRA}
}

function s3-sync-service-cfn-templates() {
    _print_info "---> Syncing CloudFormation service templates to S3 bucket ..."
    _s3_sync_cfn_templates "${PROJ_HOME}/${CFN_SERVICE}" ${CFN_S3_BUCKET_SERVICE}
}

alias "${PROJECT_NAME}-s3-sync-infra-cfn-templates"="s3-sync-infra-cfn-templates"
alias "${PROJECT_NAME}-s3-sync-service-cfn-templates"="s3-sync-service-cfn-templates"


##############################################################################
### CLOUDFORMATION
##############################################################################

# This function create CloudFormation infra stack
#
function cfn-create-stack-infra() {
    s3-sync-infra-cfn-templates

    _print_info "---> Deploying stack ${CFN_STACK_NAME_INFRA} ..."
    aws cloudformation create-stack \
        --stack-name "${CFN_STACK_NAME_INFRA}" \
        --template-url "${CFN_S3_BASE_URL_INFRA}/master.yml" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --parameters \
            ParameterKey=AdminGroupName,ParameterValue="Admin" \
            ParameterKey=ArtifactStoreBucket,ParameterValue="${S3_BUCKET_ARTIFACT}" \
            ParameterKey=CfnStackServiceName,ParameterValue="${CFN_STACK_NAME_SERVICE}" \
            ParameterKey=CFS3BaseUrl,ParameterValue="${CFN_S3_BASE_URL_INFRA}" \
            ParameterKey=CFS3BucketInfra,ParameterValue="${CFN_S3_BUCKET_INFRA}" \
            ParameterKey=CFS3BucketService,ParameterValue="${CFN_S3_BUCKET_SERVICE}" \
            ParameterKey=CloudTrailBucketName,ParameterValue="${S3_BUCKET_CLOUDTRAIL}" \
            ParameterKey=DeveloperGroupName,ParameterValue="Developer" \
            ParameterKey=DevopsGroupName,ParameterValue="Devops" \
            ParameterKey=InfrastructureRepositoryName,ParameterValue="${REPOSITORY_INFRA}" \
            ParameterKey=NotificationEndpoint,ParameterValue="${DEFAULT_EMAIL}" \
            ParameterKey=ProjectName,ParameterValue="${PROJECT_NAME}" \
            ParameterKey=ServiceRepositoryName,ParameterValue="${REPOSITORY_SERVICE}"
}


# This function create CloudFormation service stack
#
function cfn-create-stack-service() {
    s3-sync-service-cfn-templates

    _print_info "---> Deploying stack ${CFN_STACK_NAME_SERVICE} ..."
    aws cloudformation create-stack \
        --stack-name "${CFN_STACK_NAME_SERVICE}" \
        --template-url "${CFN_S3_BASE_URL_SERVICE}/master.yml" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --parameters \
            ParameterKey=CFS3BaseUrl,ParameterValue="${CFN_S3_BASE_URL_SERVICE}" \
            ParameterKey=ProjectName,ParameterValue="${PROJECT_NAME}" \
            ParameterKey=DefaultRegion,ParameterValue="${DEFAULT_REGION}" \
            ParameterKey=DefaultAccount,ParameterValue="${DEFAULT_ACCOUNT}"
}

alias "${PROJECT_NAME}-cfn-create-infra"="cfn-create-stack-infra"
alias "${PROJECT_NAME}-cfn-create-service"="cfn-create-stack-service"

# This function deploy CloudFormation bootstrap stack
#
function cfn-deploy-stack-infra() {
    s3-sync-infra-cfn-templates

    _print_info "---> Deploying stack ${CFN_STACK_NAME_INFRA} ..."
    aws cloudformation deploy \
        --stack-name "$CFN_STACK_NAME_INFRA" \
        --template-file "${PROJ_HOME}/${CFN_INFRA}/master.yml" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --parameter-overrides BranchName='develop'
}


function cfn-deploy-stack-service() {
    s3-sync-service-cfn-templates

    _print_info "---> Deploying stack ${CFN_STACK_NAME_SERVICE} ..."
    aws cloudformation deploy \
        --stack-name "$CFN_STACK_NAME_SERVICE" \
        --template-file "${PROJ_HOME}/${CFN_SERVICE}/master.yml" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
}

alias "${PROJECT_NAME}-cfn-deploy-infra"="cfn-deploy-stack-infra"
alias "${PROJECT_NAME}-cfn-deploy-service"="cfn-deploy-stack-service"


# This function clean CloudFormation stack
#
function cfn-delete-stack() {
    local stack_name=$1

    _print_info "---> Deleting stack $stack_name ..."
    aws cloudformation delete-stack --stack-name $stack_name
}

alias "${PROJECT_NAME}-cfn-delete-infra"="cfn-delete-stack $CFN_STACK_NAME_INFRA"
alias "${PROJECT_NAME}-cfn-delete-service"="cfn-delete-stack $CFN_STACK_NAME_SERVICE"
alias "${PROJECT_NAME}-cfn-delete-ecs-cluster"="cfn-delete-stack $PROJECT_NAME-ecs-cluster"



##############################################################################
### IAM
##############################################################################
function _iam_delete_user() {
    local user_name=$1

    echo "$user_name"

    _print_info "---> Deleting user '${user_name}' ..."

    if [ "${user_name}" = "${PROJECT_NAME}Admin" ]; then
        aws iam delete-login-profile --user-name "$user_name"
    fi

    aws iam delete-user --user-name "$user_name"
}

alias "${PROJECT_NAME}-iam-delete-user-admin"="_iam_delete_user ${PROJECT_NAME}Admin"


##############################################################################
### PROFILE
##############################################################################

function _aws_switch_profile() {
    local profile=$1

    _print_info "---> Switching AWS profile $profile ..."
    export AWS_PROFILE="${PROJECT_NAME}-${profile}"

    _print_info "---> Switching successfully"
}

# alias "${PROJECT_NAME}-switch-profile-default"="_aws_switch_profile default"
alias "${PROJECT_NAME}-switch-profile-admin"="_aws_switch_profile admin"
alias "${PROJECT_NAME}-switch-profile-devops"="_aws_switch_profile devops"
alias "${PROJECT_NAME}-switch-profile-developer"="_aws_switch_profile developer"


##############################################################################
### CODECOMMIT
##############################################################################

function _codecommit_create_pull_request() {
    local destination_branch=$1

    # Get current repository name
    if [ -z "${repository_name}" ]; then
        local repository_name="$(basename `git rev-parse --show-toplevel`)"
    fi

    # Get current branch name
    if [ -z "${source_branch}" ]; then
        local source_branch="$(git rev-parse --abbrev-ref HEAD)"
    fi

    _print_info "---> Creating CodeCommit pull request for branch '$source_branch' on repository '$repository_name' ..."
    aws codecommit create-pull-request \
        --title "The pull request for branch ${source_branch}" \
        --targets repositoryName="${repository_name}",sourceReference="${source_branch}",destinationReference="${destination_branch}"
}


alias "${PROJECT_NAME}-codecommit-create-pr-develop"="_codecommit_create_pull_request develop"
alias "${PROJECT_NAME}-codecommit-create-pr-master"="_codecommit_create_pull_request master"


##############################################################################
### INFORMATION
##############################################################################

function show-information() {
    _print_info "---> Loading scripts for project '${PROJECT_NAME}' ... \n
    ---> Loading scripts successfully !!!"
}

show-information


function deploy-blue-green() {
    s3-sync-infra-cfn-templates

    local stack_name="blue-green"

    _print_info "---> Deploying stack ${stack_name} ..."
    aws cloudformation deploy \
        --stack-name "$stack_name" \
        --template-file "${PROJ_HOME}/${CFN_INFRA}/ecs-public.yml" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
}
