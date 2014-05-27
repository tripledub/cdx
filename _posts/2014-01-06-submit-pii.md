---
category: Devices
path: '/results/[test_result_uuid]/pii'
title: 'Submit PII'
type: 'PUT'

layout: nil
---

Allows submission of Personal Identifiable Information into a previously submitted test result.

# Request

`/results/[test_result_uuid]/pii`

* The path must include a valid **test result UUID**.
* **The body can't be empty** and must include the PII.

# Example

```/results/c4c52784-bfd5-717d-7a91-614acd972d5e/pii```

```{
  "patient_id" : 2,
  "patient_name" : "Lorem Ipsum",
  "patient_telephone_number" : "12345678",
  "patient_zip_code" : "1234"
}```

# Response

**If succeeds**, returns the [uploaded PII](#/test-result-resource-with-pii).

`Status: 200 Ok`

For errors responses, see the [response status codes documentation](#http-response-codes).