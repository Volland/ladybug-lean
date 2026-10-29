## ADDED Requirements

### Requirement: Timeouts and interruption
The native backend SHALL run a query with a timeout, raising a timeout error when it is exceeded, and SHALL let another task interrupt a running query on a connection, raising an interrupted error in the task that ran it. The connection SHALL remain usable afterwards.

#### Scenario: Timeout
- **WHEN** a query that runs for seconds is executed with a 50 ms timeout
- **THEN** a timeout error is raised and the next query on the connection succeeds

#### Scenario: Interrupt from another task
- **WHEN** a long query runs in one task and another task interrupts the connection
- **THEN** the first task receives an interrupted error
