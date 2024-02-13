<#
.SYNOPSIS
  Creates a customer presentation PowerPoint deck using PowerShell.

.DESCRIPTION
  This script takes a Azure Well-Architected Azure VMware Solution or Azure Virtual Desktop Workload Assessment Report as input and generates a customer presentation PowerPoint deck.
  The report must be located in the same directory as the following files: 
    - GenerateWARRReport.ps1
    - WARR_PowerPointReport_Template.pptx

.PARAMETER <AssessmentReport>
    The path to the Well-Architected Assessment Report that was generated by the Microsoft Assessments platform in the following format: <pathttothereport.csv>.

.PARAMETER <AsessmentType>
    The type of Well-Architected Assessment that was performed.
    The value should be 'AVS' for an Azure VMware Solution Workload Assessment and 'AVD' for an Azure Virtual Desktop Workload Assessment.

.PARAMETER <YourName>
    Your name in the following format: <Firstname Lastname>.

.INPUTS
  This script takes a Well-Architected Assessment Report in a CSV format as input. 

.OUTPUTS
  A PowerPoint file will be created within the current directory with name in the format of: Azure Well-Architected $AssessmentType Review - Executive Summary - mmm-dd-yyyy hh.mm.ss.pptx

.NOTES
  Version:        0.1
  Author:         Farouk Friha
  Creation Date:  01/30/2024
  
.EXAMPLE
  .\GenerateWARARReport.ps1 
        -AssessmentReport ".\AVD_Well_Architected_Review_Jul_08_2022_4_35_46_PM.csv" 
        -AssessmentType AVD 
        -YourName "Farouk Friha" 

  .\GenerateWARARReport.ps1 
        -AssessmentReport ".\AVS_Well_Architected_Review_Jul_08_2022_4_35_46_PM.csv" 
        -AssessmentType AVS
        -YourName "Farouk Friha" 
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------
[CmdletBinding()]
param 
(
    [Parameter(Mandatory=$True)]
    [ValidateScript({Test-Path $_ }, ErrorMessage = "Unable to find the selected file. Please select a valid Well-Architected Assessment report in the <filename>.csv format.")]
    [string] $AssessmentReport,

    [Parameter(Mandatory=$True)]
    [ValidateSet("AVS", "AVD")]
    [string] $AssessmentType,

    [Parameter(Mandatory=$True)]
    [string] $YourName
)

#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Get the working directory from the script
$workingDirectory = (Get-Location).Path

#Get PowerPoint template and description file
$reportTemplate = "$workingDirectory\WARR_PowerPoint_Template.pptx"
$ratingDescription = @{
    "Critical" = "Based on the outcome of the assessment your workload seems to be in a critical state. Please review the recommendations for each service to resolve key deployment risks and improve your results."
    "Moderate" = "Almost there. You have some room to improve but you are on track. Review the recommendations to see what actions you can take to improve your results."
    "Excellent" = "Your workload is broadly following the principles of the Well-Architected framework. Review the recommendations to see where you can improve your results even further."
}

#Initialize variables
$localReportDate = Get-Date -Format g
$reportDate = Get-Date -Format "yyyy-MM-dd-HHmm"

#-----------------------------------------------------------[Functions]------------------------------------------------------------

#Read input file content
function Read-File($File)
{
    #Get report content
    $content = Get-Content $File

    #Get findings
    $findingsStart = $content.IndexOf("Category,Link-Text,Link,Priority,ReportingCategory,ReportingSubcategory,Weight,Context,CompleteY/N,Note")
    $endStringIdentifier = $content | Where-Object{$_.Contains("--,,")} | Select-Object -Unique -First 1
    $findingsEnd = $content.IndexOf($endStringIdentifier) - 1
    $findings = $content[$findingsStart..$findingsEnd] | Out-String | ConvertFrom-CSV -Delimiter ","
    $null = $findings | ForEach-Object { $_.Weight = [int]$_.Weight }

    #Get design areas (need consistency by keeping 'Azure Virtual Desktop -' only as a prefix and removing the rest) --> Redondant car deja present dans les scores globaux
    $designAreas = $findings | ForEach-Object { $_.Category.Split("-")[1].Trim() } | Select-Object -Unique

    #Get scores
    $startStringIdentifier = $content | Where-Object{$_.Contains("Your overall results")} | Select-Object -Unique -First 1
    $scoresStart = $content.IndexOf($startStringIdentifier) + 1
    $scoresEnd = $findingsStart - 7
    $scores = $content[$scoresStart..$scoresEnd] | Out-String | ConvertFrom-Csv -Delimiter "," -Header 'Category', 'Criticality', 'Score'
    $null = $scores | ForEach-Object { $_.Score = $_.Score.Trim("'").Replace("/100", ""); $_.Score = [int]$_.Score}
   
    #Get recommendations per design area
    [System.Collections.ArrayList]$scorecard = @{}
    
    foreach($designArea in $designAreas)
    {
        #Rating and score per design area
        $ratingPerDesignArea = ($scores | Where-Object Category -like "*$designArea*").Criticality
        $scorePerDesignArea = ($scores | Where-Object Category -like "*$designArea*").Score

        #Get recommendations per design area
        $recommendationsPerDesignArea = $findings | Where-Object Category -like "*$designArea*" | Select-Object -Property Weight, Priority, Link-Text | Sort-Object -Property Weight -Descending

        #Get weight per recommendation
        [System.Collections.ArrayList]$weightPerRecommendation = @{}

        foreach($recommendationPerDesignArea in $recommendationsPerDesignArea)
        {
            $wObject = [PSCustomObject]@{
                "Weight" = [int]($recommendationPerDesignArea.Weight)
                "Priority" = ($recommendationPerDesignArea.Priority)
                "Recommendation" = ($recommendationPerDesignArea.'Link-Text')
            }

            $null = $weightPerRecommendation.Add($wObject)
        }

        $rObject = [PSCustomObject]@{
            "Design Area" = $designArea;
            "Recommendations" = $weightPerRecommendation;
            "Score" = $scorePerDesignArea;
            "Rating" = $ratingPerDesignArea
        }

        $null = $scorecard.Add($rObject)
    }

    $scorecard = $scorecard | Sort-Object -Property Score
    $overallScore = $content[3].Split(',')[2].Trim("'").Split('/')[0]
    $overallRating = $content[3].Split(',')[1].Trim("")

    return $scorecard, $overallScore, $overallRating
}

function Edit-Slide([switch]$Chart, $Slide, $StringToFindAndReplace, $Counter)
{
    $StringToFindAndReplace.GetEnumerator() | ForEach-Object { 

        if($Chart -and ($_.Key -notlike "*DesignArea*") -and ($_.Key -notlike "*Rating*"))
        {
            $shape = $Slide.Shapes[$_.Key]

            # Edit chart serie color
            switch ([int]$_.Value)
            {
                {$_ -le 33} { $shape.Chart.SeriesCollection(1).Points(1).Interior.Color = "#FF0000" }
                {$_ -gt 33 -and $_ -le 66} { $shape.Chart.SeriesCollection(1).Points(1).Interior.Color = "#800000" }
                {$_ -gt 66} { $shape.Chart.SeriesCollection(1).Points(1).Interior.Color = "#008000" }
            }
            
            # Edit chart data
            $Slide.Shapes[$_.Key].Chart.ChartData.Workbook.Worksheets[1].Cells[2,2] = [string]$_.Value
            $Slide.Shapes[$_.Key].Chart.ChartData.Workbook.Worksheets[1].Cells[3,2] = [string](100 - $_.Value)            
        }
        else
        {
            $Slide.Shapes[$_.Key].TextFrame.TextRange.Text = [string]$_.Value
        }
    }
}

function Clear-Presentation($Slide)
{
    $slideToRemove = $Slide.Shapes | Where-Object {$_.TextFrame.TextRange.Text -match '^(Category)$'}
    $shapesToRemove = $Slide.Shapes | Where-Object {$_.TextFrame.TextRange.Text -match '^(W|Design\sarea|Sc|Priority|Rating|Recommendation)$'}
    $scoreCharts = $Slide.Shapes | Where-Object {$_.Name -match '^(Summary - Score_[1-9])$'}
    $chartsToRemove = $scoreCharts | Where-Object {$_.Chart.ChartData.Workbook.Worksheets[1].Cells[2,2].Text -eq 0}

    if ($slideToRemove)
    {
        $Slide.Delete()
    }
    else 
    {
        if ($shapesToRemove)
        {
            foreach($shapeToRemove in $shapesToRemove)
            {
                $shapeToRemove.Delete()
            }
        }

        if ($chartsToRemove) 
        {
            foreach($chartToRemove in $chartsToRemove)
            {
                $chartToRemove.Delete()
            }
        }
    }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------
#Read input file
$scorecard, $overallScore, $overallRating = Read-File -File $AssessmentReport

#Instantiate PowerPoint variables
$application = New-Object -ComObject PowerPoint.Application
$reportTemplateObject = $application.Presentations.Open($reportTemplate)
$slides = @{
    "Cover" = $reportTemplateObject.Slides[1];
    "Summary" = $reportTemplateObject.Slides[14];
    "Plan" = $reportTemplateObject.Slides[15];
    "Categories" = $reportTemplateObject.Slides[16];
    "Details" = $reportTemplateObject.Slides[17];
    "End" = $reportTemplateObject.Slides[19]
}

#Edit cover slide
$coverSlide = $slides.Cover
$stringsToReplaceInCoverSlide = @{ "Cover - Assessment_Type" = "$AssessmentType Review"; "Cover - Your_Name" = "Presented by: $YourName"; "Cover - Report_Date" = "Date: $localReportDate" }
Edit-Slide -Slide $coverSlide -StringToFindAndReplace $stringsToReplaceInCoverSlide

$i = 0

#Duplicate, move and edit summary and detail slides for each design area
foreach($designArea in $scorecard.'Design Area')
{
    $i++
    $scoreForCurrentDesignArea = $scorecard | Where-Object{$_.'Design Area'-contains $designArea}

    #Edit summary slide
    $stringsToReplaceInSummarySlide = @{ "Summary - Overall" = $overallScore; "Summary - Overall_Rating" = $overallRating; "Summary - DesignArea_$i" = $designArea; "Summary - Score_$i" = $scoreForCurrentDesignArea.score }
    Edit-Slide -Slide $slides.Summary -StringToFindAndReplace $stringsToReplaceInSummarySlide -Chart

    #Edit action plan
    if ($i -le 3)
    {
        $stringsToReplaceInPlanSlide = @{ "Plan - Category_$i" = $designArea; "Plan - Actions_$i" = ($scoreForCurrentDesignArea.Recommendations | Sort-Object -Property Weight -Descending | Select-Object -First 2).Recommendation | ForEach-Object {$_ + "`r"} }
        Edit-Slide -Slide $slides.Plan -StringToFindAndReplace $stringsToReplaceInPlanSlide
    }

    #Add score per design area
    $stringsToReplaceInCategoriesSlide = @{ "Categories - DesignArea_$i" = $designArea; "Categories - Score_$i" = [string]$scoreForCurrentDesignArea.score; "Categories - Details_$i" = $ratingDescription.($scoreForCurrentDesignArea.Rating) }
    Edit-Slide -Slide $slides.Categories -StringToFindAndReplace $stringsToReplaceInCategoriesSlide -Counter $i
    
    #Add most important recommendations
    $newDetailsSlide = $slides.Details.Duplicate()
    $newDetailsSlide.MoveTo($reportTemplateObject.Slides.Count-2)
    $stringsToReplaceInDetailsSlide = @{ "Details - DesignArea" = $designArea; "Details - Score" = $scoreForCurrentDesignArea.Score; "Details - Rating" = $scoreForCurrentDesignArea.Rating }
    Edit-Slide -Slide $newDetailsSlide -StringToFindAndReplace $stringsToReplaceInDetailsSlide

    if(($scoreForCurrentDesignArea.Recommendations | Measure-Object).Count -lt 7)
    {
        $recommendationsPerDesignArea = $scoreForCurrentDesignArea.Recommendations | Sort-Object -Property Weight -Descending | Select-Object -First ($scoreForCurrentDesignArea.Recommendations | Measure-Object).Count
    }
    else 
    {
        $recommendationsPerDesignArea = $scoreForCurrentDesignArea.Recommendations | Sort-Object -Property Weight -Descending | Select-Object -First 7
    }

    $j = 0

    foreach($recommendationPerDesignArea in $recommendationsPerDesignArea)
    {
        $j++
        $stringsToReplaceInDetailsSlide = @{ "Details - Priority_$j" = [string]$recommendationPerDesignArea.Priority; "Details - Weight_$j" = [string]$recommendationPerDesignArea.Weight; "Details - Recommendation_$j" = [string]$recommendationPerDesignArea."Recommendation"}
        Edit-Slide -Slide $newDetailsSlide -StringToFindAndReplace $stringsToReplaceInDetailsSlide
    }

    #Remove empty shapes from detail slides
    Clear-Presentation -Slide $newDetailsSlide
}

#Remove empty shapes and slides
foreach($slide in $slides.Values)
{
    Clear-Presentation -Slide $slide
}

#Save presentation and close object
$reportTemplateObject.SavecopyAs("$workingDirectory\Azure Well-Architected $AssessmentType Review - Executive Summary - $reportDate.pptx")
$reportTemplateObject.Close()

$application.quit()
$application = $null
[gc]::collect()
[gc]::WaitForPendingFinalizers()
