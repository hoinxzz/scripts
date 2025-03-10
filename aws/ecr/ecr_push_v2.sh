#!/bin/bash

ECR_ACCOUNT_ID="$2"
GRANT_ACCOUNT_IDS="$3"
REGION="ap-northeast-2"
TARGET_REPO="$ECR_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# ECR 정책을 설정하는 함수
set_ecr_policy() {
    local repo_name="$1"
    IFS=',' read -r -a grant_accounts <<< "$GRANT_ACCOUNT_IDS"

    # 정책 JSON 생성
    local policy_json='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "AllowPull",
                "Effect": "Allow",
                "Principal": {
                    "AWS": [
    '

    for account in "${grant_accounts[@]}"; do
        policy_json+="\"arn:aws:iam::$account:root\","
    done
    
    policy_json="${policy_json%,}"
    
    policy_json+='
                    ]
                },
                "Action": [
                    "ecr:BatchGetImage",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchCheckLayerAvailability"
                ]
            }
        ]
    }'

    #echo "$policy_json"  # JSON 값 확인이 필요할 때 사용
    if ! aws ecr set-repository-policy --repository-name "$repo_name" --policy-text "$policy_json" --region "$REGION"; then
        echo "오류: ECR 정책을 설정하는 데 실패했습니다."
        return 1
    fi

    echo "ECR 정책이 성공적으로 설정되었습니다: $repo_name"
    return 0
}

# 이미지를 ECR에 푸시하는 함수
image_push_to_ecr() {
    local source_image="$1"
    local target_repo="$2"
    local image_name_and_tag=$(echo "$source_image" | sed 's|/| |1' | awk '{print $2}')
    local repo_name=$(echo "$image_name_and_tag" | cut -d':' -f1)

    # ECR 리포지토리 확인 및 생성
    if ! aws ecr describe-repositories --repository-names "$repo_name" --region $REGION > /dev/null 2>&1; then
        echo "ECR 레포지토리가 존재하지 않습니다. 레포지토리를 생성합니다: $repo_name"
        aws ecr create-repository --repository-name "$repo_name" --region $REGION
    fi
    ## ECR Policy 설정이 필요없다면 주석, 현재 적용되어있는 정책도 바꾸기 때문에 주의 필요
    set_ecr_policy "$repo_name"

    # docker Image Pull, Tag, ECR 로그인 및 푸시를 하나의 if 문 안에서 수행
    if docker pull "$source_image" && \
       docker tag "$source_image" "${target_repo}/${image_name_and_tag}" && \
       aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$target_repo" && \
       docker push "${target_repo}/${image_name_and_tag}"; then
        echo "이미지 '${source_image}'를 성공적으로 ECR에 푸시했습니다."
        remove_local_images
    else
        echo "오류: 이미지를 ECR에 푸시하는 데 실패했습니다."
        return 1
    fi

    return 0
}

# 로컬 이미지를 삭제하는 함수
remove_local_images() {
    local local_image_ids=$(docker images -q | uniq)
    if [[ -n "$local_image_ids" ]]; then
        for image_id in $local_image_ids; do
            docker rmi --force "$image_id"
            echo "로컬에서 이미지 ID '$image_id'가 성공적으로 삭제되었습니다."
        done
    else
        echo "삭제할 로컬 이미지가 없습니다."
    fi
}

# 인자 체크
if [[ -z "$1" || -z "$2" || -z "$3" ]]; then
    echo "사용법: $0 <이미지 목록 파일> <ECR 계정 ID> <권한 부여 계정 ID(쉼표로 구분)>"
    exit 1
fi

# 첫 번째 인자가 파일인지 체크하고, 파일이 존재하는지 체크
if [[ ! -f "$1" ]]; then
    echo "오류: 파일 '$1'이(가) 존재하지 않습니다."
    exit 1
fi

# 파일을 읽어서 docker_operations을 실행
while IFS= read -r image; do
    if [[ -n "$image" ]]; then
        image_push_to_ecr "$image" "$TARGET_REPO"
    fi
done < "$1"
