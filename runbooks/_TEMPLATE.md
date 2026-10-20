# RB-XX — <Short title>

| | |
|---|---|
| **Cluster** | VKE / kubeadm / both |
| **Layer** | Storage / Network / Compute / Control plane / Vultr integration |
| **Concept demonstrated** | one line |
| **Severity (as a ticket)** | P1–P4 |

## Symptom
What the customer would report, in their words. One or two sentences.

## Reproduce
Exact commands to cause it.

## Diagnose
The investigation path, in order. Every command here is also a **proof capture**:
save the output to `runbooks/evidence/RB-XX/<step>.txt` (or a screenshot).

```
kubectl ...
```

What each output tells you, and what it rules out.

## Root cause
One paragraph. Name the component (CCM, CSI, Calico, kubelet, Vultr API…).

## Fix
Commands. Then the command that proves it's fixed.

## Prevention / what I'd tell the customer
Two or three sentences. This is the part a Sr. TSE is judged on.

## Evidence captured
- [ ] `evidence/RB-XX/01-symptom.txt`
- [ ] `evidence/RB-XX/02-describe.txt`
- [ ] `evidence/RB-XX/03-fixed.txt`
