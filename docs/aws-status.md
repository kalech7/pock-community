# AWS Status

Open **Widgets → Manage widgets… → AWS Status → Configure AWS Status…** to enable the widget and choose its indicators. Use **Organize Widgets…** to place it in the main or second Touch Bar menu. Tap AWS Status on the Touch Bar to see the last check, errors, and a refresh button.

## EC2 and RDS

Install [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and select a configured profile and the region that contains your resources. EC2 requires `ec2:DescribeInstances`. RDS requires `rds:DescribeDBInstances`. Pock uses the local AWS CLI configuration and displays only standard diagnostic messages. Profile credentials, account IDs, and raw CLI errors should stay out of public issue reports.

If the widget reports an expired session, renew the configured profile using the login method you originally used. An empty resource list is expected when the selected region contains no matching instances. A permission error means the profile needs the relevant Describe permission. See [AWS CLI troubleshooting](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-troubleshooting.html).

## Local indicators

**Last job** reads a JSON file you select. Use a status of `ok`, `error`, or `running`. Supply either `finished_at` or `last_completed_at` as an ISO 8601 date and time for the latest completed run.

```json
{
  "status": "ok",
  "finished_at": "2026-11-24T09:00:00Z"
}
```

**Cost** reads a local JSON snapshot or an estimate already cached by a local build. Supply UTC timestamps with `end` as the exclusive last day and an ISO currency code. You can show the total so far or project the average daily spend across the month. The widget marks a stale estimate and shows its timestamp in the details.

```json
{
  "start": "2026-11-01T00:00:00Z",
  "end": "2026-11-25T00:00:00Z",
  "checkedAt": "2026-11-25T12:00:00Z",
  "unit": "USD",
  "lines": [
    {
      "service": "Amazon Relational Database Service",
      "amount": 4.25
    }
  ]
}
```
