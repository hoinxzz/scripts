#!/bin/bash

ECR_ACCOUNT_ID="$2"
GRANT_ACCOUNT_IDS="$3"
REGION="ap-northeast-2"
TARGET_REPO="$ECR_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# ECR 정책을 설정하는 함수
set_ecr_policy() {
    local repo_name="$1"

    # ECR 정책 추가
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
    ########
    ###json 값 확인 시 주석 해제
    echo "$policy_json"
    if ! aws ecr set-repository-policy --repository-name "$repo_name" --policy-text "$policy_json" --region "$REGION"; then
        echo "오류: ECR 정책을 설정하는 데 실패했습니다."
        return 1
    fi

    echo "ECR 정책이 성공적으로 설정되었습니다: $repo_name"
    return 0
}

# 이미지 `repo:tag`와 대상 repo를 정보로 받아 docker pull, docker tag, docker push를 실행하는 함수
image_push_to_ecr() {
    local source_image="$1"
    local target_repo="$2"
    local image_name_and_tag=$(echo "$source_image" | sed 's|/| |1' | awk '{print $2}')
    local repo_name=$(echo "$image_name_and_tag" | cut -d':' -f1)

    if ! aws ecr describe-repositories --repository-names "$repo_name" --region $REGION > /dev/null 2>&1; then
        echo "ECR 레포지토리가 존재하지 않습니다. 레포지토리를 생성합니다: $repo_name"
        aws ecr create-repository --repository-name "$repo_name" --region $REGION
    fi
    set_ecr_policy "$repo_name" 

    # docker Image Pull, Tag, ECR 로그인 및 푸시를 하나의 if 문 안에서 수행
    if docker pull "$source_image"; then
        if docker tag "$source_image" "${target_repo}/${image_name_and_tag}"; then
            if aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$target_repo"; then
                if docker push "${target_repo}/${image_name_and_tag}"; then
                    echo "이미지 '${source_image}'를 성공적으로 ECR에 푸시했습니다."
                    ## 대량의 이미지 업로드 시 사용(도커 이미지 디스크 Pull 시)
                    ## 이미지 ID를 변수에 저장
                    #local_image_ids=$(docker images -q | uniq)
                    #
                    ## 로컬 이미지 삭제
                    #if [[ -n "$local_image_ids" ]]; then
                    #    for image_id in $local_image_ids; do
                    #        docker rmi --force "$image_id"
                    #    done
                    #else
                    #    echo "삭제할 로컬 이미지가 없습니다."
                    #fi
                else
                    echo "오류: '${target_repo}/${image_name_and_tag}' 이미지를 푸시하는 데 실패했습니다."
                    return 1
                fi
            else
                echo "오류: ECR에 로그인하는 데 실패했습니다."
                exit 1
            fi
        else
            echo "오류: 이미지 태그 설정 중 실패했습니다."
            return 1
        fi
    else
        echo "$source_image 이미지 Pull 진행 중 오류가 발생했습니다."
        return 1
    fi

    return 0
}

# 인자 체크
if [[ -z "$1" || -z "$2" || -z "$3" ]]; then
    echo "사용법: $0 <이미지 목록 파일> <ECR 계정 ID> <권한 부여 계정 ID(쉼표로 구분)>"
    [[ -z "$1" ]] && echo "오류: 이미지 목록 파일이 지정되지 않았습니다."
    [[ -z "$2" ]] && echo "오류: ECR 계정 ID가 지정되지 않았습니다."
    [[ -z "$3" ]] && echo "오류: 권한 부여 계정 ID가 지정되지 않았습니다."
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
