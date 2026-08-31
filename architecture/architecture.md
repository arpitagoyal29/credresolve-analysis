```mermaid
flowchart LR
    Raw["Raw<br/>17 source tables"] --> Staging["Staging<br/>schema cast"]
    Staging --> Clean["Clean<br/>dedupe + canonicalize"]
    Clean --> Golden["Golden<br/>account_id-only joins"]
    Golden --> Feature["Feature<br/>account/agent rollups"]
    Feature --> Metrics["Metrics<br/>versioned KPI defs"]
    Metrics --> Dashboard["Dashboard<br/>always shows trend"]

    Raw -.-> DQ1["row-count check"]
    Clean -.-> DQ2["PK + FK check"]
    Golden -.-> DQ3["id-match regression"]
    Metrics -.-> DQ4["control-band anomaly"]

        style Golden fill:#fff3bf,stroke:#f59e0b,stroke-width:2px,color:#1a1a1a
    style Dashboard fill:#b2f2bb,stroke:#22c55e,stroke-width:2px,color:#1a1a1a
    style DQ1 fill:#ffc9c9,stroke:#ef4444,color:#1a1a1a
    style DQ2 fill:#ffc9c9,stroke:#ef4444,color:#1a1a1a
    style DQ3 fill:#ffc9c9,stroke:#ef4444,color:#1a1a1a
    style DQ4 fill:#ffc9c9,stroke:#ef4444,color:#1a1a1a
```