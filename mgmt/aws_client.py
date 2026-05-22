import os
import boto3
import logging

logger = logging.getLogger(__name__)

AWS_REGION = os.getenv("AWS_REGION", "ap-northeast-2")

cw  = boto3.client("cloudwatch",  region_name=AWS_REGION)
asg = boto3.client("autoscaling", region_name=AWS_REGION)
ec2 = boto3.client("ec2",         region_name=AWS_REGION)

# Terraform compute-gangnam.tf 기준 (namespace="cgst", metric="gangnam-cgst")
NAMESPACE = "cgst"
METRIC_NAMES = {
    "강남구": "gangnam-cgst",
    "은평구": "eunpyeong-cgst",
}

# Terraform locals.tf 기준 (name_prefix="bugTeam")
ASG_NAMES = {
    "강남구": os.getenv("ASG_GANGNAM",   "bugTeam-asg-gangnam"),
    "은평구": os.getenv("ASG_EUNPYEONG", "bugTeam-asg-eunpyeong"),
}


SCALE_POLICY = [
    (10,  0),   # 0~10   한적 → 인스턴스 0대 (오토스탑)
    (60,  1),   # 11~60  원활 → 인스턴스 1대
    (100, 2),   # 61~100 혼잡 → 인스턴스 2대
]


def get_desired_capacity(avg_cgst: float) -> int:
    for threshold, capacity in SCALE_POLICY:
        if avg_cgst <= threshold:
            return capacity
    return 2


def scale_asg(sgg_nm: str, avg_cgst: float):
    """혼잡도에 따라 ASG 목표 대수를 직접 설정."""
    asg_name = ASG_NAMES.get(sgg_nm)
    if not asg_name:
        logger.warning(f"scale_asg: 알 수 없는 지역 {sgg_nm}")
        return
    desired = get_desired_capacity(avg_cgst)
    try:
        asg.set_desired_capacity(
            AutoScalingGroupName=asg_name,
            DesiredCapacity=desired,
            HonorCooldown=False,
        )
        logger.info(f"ASG 조정 완료: {asg_name} → {desired}대 (avg_cgst={avg_cgst})")
    except Exception as e:
        logger.warning(f"ASG 조정 실패 ({asg_name}): {e}")


def push_metric(sgg_nm: str, avg_cgst: float):
    """평균 혼잡도를 CloudWatch에 push → CloudWatch 알람 → ASG Step Scaling 자동 발동."""
    metric_name = METRIC_NAMES.get(sgg_nm)
    if not metric_name:
        logger.warning(f"알 수 없는 지역: {sgg_nm}")
        return
    try:
        cw.put_metric_data(
            Namespace=NAMESPACE,
            MetricData=[{
                "MetricName": metric_name,
                "Value":      avg_cgst,
                "Unit":       "None",
            }]
        )
        logger.info(f"CloudWatch push 완료: {metric_name} = {avg_cgst}")
    except Exception as e:
        logger.warning(f"CloudWatch push 실패 ({metric_name}): {e}")


def get_asg_status(sgg_nm: str) -> dict:
    """ASG 현황(목표/실행 대수, 인스턴스 IP 목록) 조회."""
    asg_name = ASG_NAMES.get(sgg_nm)
    if not asg_name:
        return {"desired": 0, "running": 0, "instances": []}
    try:
        resp   = asg.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])
        groups = resp.get("AutoScalingGroups", [])
        if not groups:
            return {"desired": 0, "running": 0, "instances": []}

        g            = groups[0]
        instance_ids = [i["InstanceId"] for i in g.get("Instances", [])]
        instances    = []

        if instance_ids:
            ec2_resp = ec2.describe_instances(InstanceIds=instance_ids)
            for reservation in ec2_resp["Reservations"]:
                for inst in reservation["Instances"]:
                    instances.append({
                        "instance_id": inst["InstanceId"],
                        "private_ip":  inst.get("PrivateIpAddress", "-"),
                        "state":       inst["State"]["Name"],
                    })

        return {
            "desired":   g["DesiredCapacity"],
            "running":   sum(1 for i in g.get("Instances", []) if i["LifecycleState"] == "InService"),
            "instances": instances,
        }
    except Exception as e:
        logger.warning(f"get_asg_status({sgg_nm}): {e}")
        return {"desired": 0, "running": 0, "instances": []}
