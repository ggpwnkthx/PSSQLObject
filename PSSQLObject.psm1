# Prerequisites
if (!((Get-Module).Name -contains "SqlServer")) {
    Install-Module -Name SqlServer  -Scope CurrentUser
}

# Main Class
Class PSSQLObject {
    [string]$Server
    [string]$Database
    [PSCredential]$Credentials

    [Array]$Keys
    [Array]$Relations
    [Object]$Tables

    PSSQLObject([string]$Server, [string]$Database, [PSCredential]$Credentials) {
        $this.Server = $Server
        $this.Database = $Database
        $this.Credentials = $Credentials
        $this.Construct()
    }
    PSSQLObject([string]$Server, [string]$Database) {
        $this.Server = $Server
        $this.Database = $Database
        $this.Credentials = $null
        $this.Construct()
    }
    Construct() {
        $this.Tables = New-Object PSObject
        $this.Query("SELECT TABLE_NAME FROM [INFORMATION_SCHEMA].[TABLES]").TABLE_NAME | Foreach {
            $this.Tables | Add-Member -MemberType NoteProperty -Name $_ -Value @()
        }
        $this.Keys = $this.Query("
            SELECT 
                b.TABLE_CATALOG,
                b.TABLE_SCHEMA,
                b.TABLE_NAME,
                b.COLUMN_NAME
            FROM
                [sys].[key_constraints] AS a
            INNER JOIN
                [INFORMATION_SCHEMA].[KEY_COLUMN_USAGE] AS b
                    ON a.name = b.CONSTRAINT_NAME
        ")
        $this.Relations = $this.Query("
            SELECT 
                b.TABLE_CATALOG as LINK_CATALOG,
                b.TABLE_SCHEMA as LINK_SCHEMA,
                b.TABLE_NAME as LINK_TABLE,
                b.COLUMN_NAME as LINK_COLUMN,
                c.TABLE_CATALOG as TARGET_CATALOG,
                c.TABLE_SCHEMA as TARGET_SCHEMA,
                c.TABLE_NAME as TARGET_TABLE,
                c.COLUMN_NAME as TARGET_COLUMN
            FROM
                [INFORMATION_SCHEMA].[REFERENTIAL_CONSTRAINTS] AS a
            INNER JOIN
                [INFORMATION_SCHEMA].[KEY_COLUMN_USAGE] as b
                    ON a.CONSTRAINT_CATALOG = b.CONSTRAINT_CATALOG AND a.CONSTRAINT_SCHEMA = b.CONSTRAINT_SCHEMA AND a.CONSTRAINT_NAME = b.CONSTRAINT_NAME
            INNER JOIN
                [INFORMATION_SCHEMA].[KEY_COLUMN_USAGE] as c
                    ON a.UNIQUE_CONSTRAINT_CATALOG = c.CONSTRAINT_CATALOG AND a.UNIQUE_CONSTRAINT_SCHEMA = c.CONSTRAINT_SCHEMA AND a.UNIQUE_CONSTRAINT_NAME = c.CONSTRAINT_NAME
        ")
    }
    
    # Standardized Query
    [Array]Query([string]$Query) {
        if($this.Credentials -eq $null) {
            return Invoke-Sqlcmd -Query $Query -ServerInstance $this.Server -Database $this.Database
        } else {
            return Invoke-Sqlcmd -Query $Query -ServerInstance $this.Server -Database $this.Database -Credential $this.Credentials
        }
    }
    
    # Cache Results from the Standardized Query
    Cache([string]$Table, [string]$Column, [string]$Comparator, [string]$Value) {
        # Make sure there is an array of tables names
        if (-not ([string]::IsNullOrEmpty($Table))) {
            $ta = @($Table)
        } else {
            $ta = $this.Tables.PSObject.Properties.Name
        }
        
        # Iterate through the array of table names
        $index_t = 1
        foreach ($t in $ta) {
            # Provide a progress bar for the iteration of tables
            [string]$status_t = $index_t
            $status_t += "/"
            $status_t += $ta.Length
            $status_t += " : "
            $status_t += $t
            $percent_t = ($index_t / $ta.Length) * 100
            Write-Progress -Activity "Dumping SQL data into local RAM" -Status $status_t -PercentComplete $percent_t -Id "1"
            $index_t++
            
            # Build the query string based
            $query = "SELECT * FROM "
            $query += $t
            if (-not ([string]::IsNullOrEmpty($Column))) {
                $query += " WHERE "
                $query += $Column
                $query += " "
                $query += $Comparator
                $query += " "
                $query += $Value
            }
            
            # Run the query
            $rows = $this.Query($query)
            
            # Replace Key Column values with PSSQLLink
            $relatives = $this.Relations | Where-Object {$_.LINK_TABLE -eq $t}
            foreach ($r in $rows) {
                $relatives | Foreach {
                    $rel = $null
                    if (-not ([string]::IsNullOrEmpty($r.($_.LINK_COLUMN)))) {
                        $rel = [PSSQLLink]::new([ref]$this, [ref]$_, $r.($_.LINK_COLUMN))
                    }
                    $r.PSObject.Properties.Remove($_.LINK_COLUMN)
                    $r | Add-Member -MemberType NoteProperty -Name $_.LINK_COLUMN -Value $rel -Force
                }
            }
            
            # Cache logisitcs
            if ($this.Tables.PSObject.Properties.Name -contains $t -and -not ([string]::IsNullOrEmpty($Value))) {
                $t_keys = @($this.Keys | Where-Object { $_.TABLE_NAME -eq $t })
                if ($t_keys.Count -gt 0) {
                    $filter = ""
                    $index_k = 1
                    foreach ($k in $t_keys.COLUMN_NAME) {
                        if ($index_k -gt 1) {
                            $filter += " -and "
                        }
                        $filter += "`$_."
                        $filter += $k
                        $filter += " -ne `$r."
                        $filter += $k
                        $index_k++
                    }
                    $filter_sb = [System.Management.Automation.ScriptBlock]::Create($filter)
                    
                    $index_r = 1
                    foreach ($r in $rows) {
                        [string]$status_r = $index_r
                        $status_r += "/"
                        $status_r += $rows.Length
                        $percent_r = ($index_r / $rows.Length) * 100
                        Write-Progress -Activity "Updating Cache" -Status $status_r -PercentComplete $percent_r -Id "2" -ParentId "1"
                        $index_r++
                        $this.Tables.$t = @($this.Tables.$t | Where-Object -FilterScript $filter_sb)
                        $this.Tables.$t += $r
                    }
                }
            } else {
                $this.Tables.$t = $rows
            }
        }
    }
    # Overload when $Comparator is presumed to be "="
    Cache([string]$Table, [string]$Column, [string]$Value) {
        $this.Cache($Table, $Column, "=", $Value)
    }
    # Overload that will download and cache an entire table.
    Cache([string]$Table) {
        $this.Cache($Table, $null, $null, $null)
    }
    # Overload that will download and cache the entire database.
    Cache() {
        $this.Cache($null, $null, $null, $null)
    }
    
    # Caches the query if it does not already exist, and returns the row
    [Object]Get([string]$Table, [string]$Column, $Value) {
        $r = @($this.Tables.$Table | Where-Object -Property $Column -EQ -Value $Value)
        if ($r.Count -eq 0) {
            $this.Cache($Table, $Column, $Value)
            $r = @($this.Tables.$Table | Where-Object -Property $Column -EQ -Value $Value)
        }
        return $r
    }
}

# Helper Classes
Class PSSQLLink {
    [ref]$SQL
    [ref]$Relative
    $Value

    PSSQLLink([ref]$SQL, [ref]$Relative, $Value) {
        $this.SQL = $SQL
        $this.Relative = $Relative
        $this.Value = $Value
    }
    
    # Returns the targeted row
    [Object]Target() {
        return $this.SQL.Value.Get($this.Relative.Value.TARGET_TABLE, $this.Relative.Value.TARGET_COLUMN, $this.Value)
    }
}
